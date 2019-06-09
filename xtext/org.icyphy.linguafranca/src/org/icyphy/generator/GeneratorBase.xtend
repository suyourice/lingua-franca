/*
 * Generator base class for shared code between code generators.
 */
// The Lingua-Franca toolkit is is licensed under the BSD 2-Clause License.
// See LICENSE.md file in the top repository directory.
package org.icyphy.generator

import java.text.NumberFormat
import java.text.ParseException
import java.util.HashMap
import java.util.HashSet
import java.util.Hashtable
import java.util.LinkedHashMap
import java.util.LinkedList
import org.eclipse.emf.ecore.EObject
import org.eclipse.emf.ecore.resource.Resource
import org.eclipse.xtext.generator.IFileSystemAccess2
import org.eclipse.xtext.generator.IGeneratorContext
import org.eclipse.xtext.nodemodel.util.NodeModelUtils
import org.icyphy.linguaFranca.Connection
import org.icyphy.linguaFranca.Instance
import org.icyphy.linguaFranca.LinguaFrancaFactory
import org.icyphy.linguaFranca.Reaction
import org.icyphy.linguaFranca.Reactor
import org.icyphy.linguaFranca.Time

/**
 * Generator base class for shared code between code generators.
 * 
 * @author Edward A. Lee, Marten Lohstroh, Chris Gill
 */
class GeneratorBase {
	
	// Map from a reactor to properties of the reactor.
	protected var reactorToProperties = new HashMap<Reactor,ReactorProperties>()
	
	// Map from reactor name to the AST reactor defining that class.
	var classToReactor = new LinkedHashMap<String,Reactor>()

	// All code goes into this string buffer.
	var code = new StringBuilder
	
	// Map from builder to its current indentation.
	var indentation = new HashMap<StringBuilder,String>()
	
	// The main (top-level) reactor instance.
	protected ReactorInstance main 
	
	// Map from time units to an expression that can convert a number in
	// the specified time unit into nanoseconds. This expression may need
	// to have a suffix like 'LL' or 'L' appended to it, depending on the
	// target language, to ensure that the result is a 64-bit long.
	static public var timeUnitsToNs = #{
			'nsec' -> 1L,
		 	'usec' -> 1000L,
			'msec'->1000000L,
			'sec'->1000000000L,
			'secs'->1000000000L,
			'minute'->60000000000L,
			'minutes'->60000000000L,
			'hour'->3600000000000L,
			'hours'->3600000000000L,
			'day'->86400000000000L,
			'days'->86400000000000L,
			'week'->604800000000000L, 
			'weeks'->604800000000000L}
	
	////////////////////////////////////////////
	//// Code generation functions to override for a concrete code generator.
	
	/** Generate code from the Lingua Franca model contained by the
	 *  specified resource. This is the main entry point for code
	 *  generation. This base class invokes generateReactor()
	 *  for each contained reactor.
	 *  @param resource The resource containing the source code.
	 *  @param fsa The file system access (used to write the result).
	 *  @param context FIXME
	 *  @param importTable The mapping given by import statements.
	 */
	def void doGenerate(
			Resource resource, 
			IFileSystemAccess2 fsa,
			IGeneratorContext context,
			Hashtable<String,String> importTable) {
		// Generate reactors and composites.
		main = null
		for (reactor : resource.allContents.toIterable.filter(Reactor)) {
			generateReactor(reactor, importTable)
			if (reactor.name.equalsIgnoreCase("main")) {
				main = new ReactorInstance(reactor)
			}
		}
		if (main !== null) {
			// Instantiate the "main" reactor.
			var mainInstance = LinguaFrancaFactory.eINSTANCE.createInstance()
			mainInstance.setName(main.reactor.name)
			mainInstance.setReactorClass(main.reactor.name)
			main.instanceStatement = mainInstance
			// FIXME: Should use mainInstance.setParameters() to set parameter
			// values from the command line.
			instantiate(mainInstance, null, importTable)
		} else {
			reportWarning(resource.allContents.next, "No Main reactor.")
		}
	}
	
	/** Collect data in a reactor or composite definition.
	 *  Subclasses should override this and be sure to call
	 *  super.generateReactor(reactor, importTable).
	 *  @param reactor The parsed reactor AST data structure.
	 *  @param importTable Substitution table for class names (from import statements).
	 */	
	def void generateReactor(Reactor reactor, Hashtable<String,String> importTable) {
				
		// Reset indentation, in case it has gotten messed up.
		indentation.put(code, "")
		
		classToReactor.put(reactor.name, reactor)
		
		// Create the object for storing reactor properties.
		var properties = new ReactorProperties()
		reactorToProperties.put(reactor, properties)

		// Record parameters.
		if (reactor.parameters !== null) {
			for (param : reactor.parameters.params) {
				properties.nameToParam.put(param.name, param)
			}
		}
		
		// Record inputs.
		for (input: reactor.inputs) {
			properties.nameToInput.put(input.name, input)
		}
		
		// Record outputs.
		for (output: reactor.outputs) {
			properties.nameToOutput.put(output.name, output)
		}
		
		// Record actions.
		for (action: reactor.actions) {
			if (action.getDelay() === null) {
				action.setDelay("0")
			}
			properties.nameToAction.put(action.name, action)
		}
		
		// Record timers.
		for (timer: reactor.timers) {
			properties.nameToTimer.put(timer.name, timer)
			var timing = timer.timing
			// Make sure every timing object has both an offset
			// and a period by inserting default of 0.
			var zeroTime = LinguaFrancaFactory.eINSTANCE.createTime()
			zeroTime.setTime("0")
			if (timing === null) {
				timing = LinguaFrancaFactory.eINSTANCE.createTiming()
				timing.setOffset(zeroTime)
				timing.setPeriod(zeroTime)
			} else if (timing.getPeriod === null) {
				timing.setPeriod(zeroTime)
			}
			
			properties.nameToTiming.put(timer.name, timing)
		}
		
		// Record the reactions triggered by each trigger.
		for (reaction: reactor.reactions) {
			// Iterate over the reaction's triggers
			if (reaction.triggers !== null && reaction.triggers.length > 0) {
				for (trigger: reaction.triggers) {
					// Check validity of the trigger.
					if (properties.nameToInput.get(trigger) === null
							&& getTiming(reactor, trigger) === null
							&& getAction(reactor, trigger) === null) {
                        reportError(reaction,
                        		"Trigger '" + trigger + "' is neither an input, a timer, nor an action.")
                    }
                    var reactionList = properties.triggerNameToReactions.get(trigger)
                    if (reactionList === null) {
                    	reactionList = new LinkedList<Reaction>()
						properties.triggerNameToReactions.put(trigger, reactionList)
                    }
                    reactionList.add(reaction)
				}	
			}
		}
		// Record contained instances.
		for (instance: reactor.instances) {
			properties.nameToInstance.put(instance.name, instance)
		}
		// Record (and check) connections.
		for (connection: reactor.connections) {
			var split = connection.leftPort.split('\\.')
			if (split.length === 1) {
				// It is a local input port.
				if (getInput(reactor, connection.leftPort) === null) {
					reportError(connection,
							"Left side is not an input port of this composite: " + connection.leftPort)
				}
			} else if (split.length === 2) {
				// Form is reactorName.portName.
				var instance = properties.nameToInstance.get(split.get(0))
				if(instance === null) {
					reportError(connection,
							"No such instance: " + split.get(0))
				} else {
					var contained = getReactor(instance.reactorClass)
					// Contained object may be imported, i.e. not a Lingua Franca object.
					// Cannot check here.
					if (contained !== null) {
						var props = reactorToProperties.get(contained)
						if(props.nameToOutput.get(split.get(1)) === null) {
							reportError(connection,
									"No such output port: " + connection.leftPort)
						}
					}
				}
			} else {
				reportError(connection, "Invalid port specification: " + connection.leftPort)
			}
			// Check the right port.
			split = connection.rightPort.split('\\.')
			if (split.length === 1) {
				// It is a local input port.
				if (getOutput(reactor, connection.rightPort) === null) {
					reportError(connection,
							"Right side is not an output port of this reactor: " + connection.rightPort)
				}
			} else if (split.length === 2) {
				// Form is reactorName.portName.
				var instance = properties.nameToInstance.get(split.get(0))
				if(instance === null) {
					reportError(connection,
							"No such instance: " + split.get(0))
				} else {
					var contained = getReactor(instance.reactorClass)
					// Contained object may be imported, i.e. not a Lingua Franca object.
					// Cannot check here.
					if (contained !== null) {
						var props = reactorToProperties.get(contained)
						if(props.nameToInput.get(split.get(1)) === null) {
							reportError(connection,
									"No such input port: " + connection.rightPort)
						}
					}
				}
			} else {
				reportError(connection, "Invalid port specification: " + connection.rightPort)
			}
			// Record the source-destination pair.
			var destinations = properties.outputNameToInputNames.get(connection.leftPort)
			if (destinations === null) {
				destinations = new HashSet<String>()
				properties.outputNameToInputNames.put(connection.leftPort, destinations)
			}
			destinations.add(connection.rightPort)
		}
	}
	
	/** For the given reactor, create instances of each reactor
	 *  that it contains.
	 *  @param reactor The reactor.
	 *  @param container The instance that is the container.
	 *  @param importTable The table of imports.
	 */
	def void generateContainedInstances(
		Reactor reactor,
		ReactorInstance container,
		Hashtable<String,String> importTable
	) {
		// Generated instances
		for (instance: reactor.instances) {
			var contained = instantiate(instance, container, importTable)
			if (contained !== null) {
				container.addContainedInstance(contained)
			}
		}
		// Handle connections
		for (connection: reactor.connections) {
			connect(connection)
		}
	}
	
	/** Handle a connection
	 *  @param connection The connection.
	 */
	def connect(Connection connection) {
		// FIXME Generate code to initialize the input's "this" struct's
		// input field to point to the output's "this" struct's output
		// field. Do the same for _is_present fields.
	}
	
	/** Instantiate a reactor.
	 *  @param instance The instance declaration.
	 *  @param container The instance that is the container.
	 *  @param importTable Substitution table for class names (from import statements).
	 */
	def instantiate(
		Instance instance,
		ReactorInstance container,
		Hashtable<String,String> importTable
	) {
		var reactor = getReactor(instance.reactorClass)
		// If there is no container, then the reactorInstance is main.
		// Otherwise, create a new one.
		var reactorInstance = main
		if (container !== null) {
			reactorInstance = new ReactorInstance(reactor, instance, container)
		}
		// Reactor may be imported, i.e. not a Lingua Franca reactor,
		// in which case, reactor === null.
		// In case the reactor is a composite, create instances of
		// whatever it instantiates.
		generateContainedInstances(reactor, reactorInstance, importTable)
		reactorInstance
	}
	
	////////////////////////////////////////////
	//// Utility functions for generating code.
	
	/** Clear the buffer of generated code.
	 */
	protected def clearCode() {
		code = new StringBuilder
	}
	
	/** Return the Action with the given name.
	 *  @param reactor The Reactor.
	 *  @param name The name of the desired action.
	 *  @return The action, or null if there isn't one.
	 */
	protected def getAction(Reactor reactor, String name) {
		var properties = reactorToProperties.get(reactor)
		properties.nameToAction.get(name)
	}
	
	/** Get the code produced so far.
	 *  @return The code produced so far as a String.
	 */
	protected def getCode() {
		code.toString()
	}
	
	/** Return the Input with the given name.
	 *  @param reactor The Reactor.
	 *  @param name The name of the desired input.
	 *  @return The input, or null if there isn't one.
	 */
	protected def getInput(Reactor reactor, String name) {
		var properties = reactorToProperties.get(reactor)
		properties.nameToInput.get(name)
	}
	
	/** Return the Instance with the given name.
	 *  @param reactor The container Reactor.
	 *  @param name The name of the desired instance.
	 *  @return The instance, or null if there isn't one.
	 */
	protected def getInstance(Reactor reactor, String name) {
		var properties = reactorToProperties.get(reactor)
		properties.nameToInstance.get(name)
	}
	
	/** Return the Output with the given name.
	 *  @param reactor The Reactor.
	 *  @param name The name of the desired output.
	 *  @return The output, or null if there isn't one.
	 */
	protected def getOutput(Reactor reactor, String name) {
		var properties = reactorToProperties.get(reactor)
		properties.nameToOutput.get(name)
	}
	
	/** Return the parameter with the given name.
	 *  @param reactor The Reactor.
	 *  @param name The name of the desired parameter.
	 *  @return The parameter, or null if there isn't one.
	 */
	protected def getParameter(Reactor reactor, String name) {
		var properties = reactorToProperties.get(reactor)
		properties.nameToParam.get(name)
	}
	
	/** Return the parameters defined for the specified reactor.
	 *  @param reactor The reactor.
	 *  @return The parameters for the reactor.
	 */
	protected def getParameters(Reactor reactor) {
		var properties = reactorToProperties.get(reactor)
		properties.nameToParam.values()
	}

	/** Get the list of reactions triggered by the specified trigger
	 *  for the specified reactor.
	 *  @param reactor The reactor.
	 *  @param name The name of the trigger (input, action, or timer).
	 *  @return A list of Reaction objects or null if there are none.
	 */
	protected def getReactions(Reactor reactor, String name) {
		var properties = reactorToProperties.get(reactor)
		properties.triggerNameToReactions.get(name)
	}

	/** Get the AST element defining a reactor that has
	 *  the specified class name, or null if there is none.
	 *  @param className The reactor class name.
	 *  @return The reactor, or null if there isn't one matching the name.
	 */
	protected def getReactor(String className) {
		classToReactor.get(className)
	}

	/** Return a set of timer names for a reactor class.
	 */
	protected def getTimerNames(Reactor reactor) {
		var properties = reactorToProperties.get(reactor)
		properties.nameToTimer.keySet()
	}
	
	/** Get the timer with the specified name in the specified reactor.
	 *  @param reactor The reactor.
	 *  @param name The name of the timer.
	 *  @return A Timer object or null if there is no timer with the specified name.
	 */
	protected def getTimer(Reactor reactor, String name) {
		var properties = reactorToProperties.get(reactor)
		properties.nameToTimer.get(name)
	}
	
	/** Get the timing of the timer with the specified name in the specified reactor.
	 *  @param reactor The reactor.
	 *  @param name The name of the timer.
	 *  @return A Timing object or null if there is no timer with the specified name.
	 */
	protected def getTiming(Reactor reactor, String name) {
		var properties = reactorToProperties.get(reactor)
		properties.nameToTiming.get(name)
	}
	
	/** Get the map from triggers to the list of reactions
	 *  triggered by the trigger for the specified reactor.
	 *  @param reactor The reactor.
	 *  @return A map from triggers to the list of reactions triggered.
	 */
	protected def getTriggerToReactions(Reactor reactor) {
		var properties = reactorToProperties.get(reactor)
		properties.triggerNameToReactions
	}
	
	/** Increase the indentation of the output code produced.
	 */
	protected def indent() {
		indent(code)
	}
	
	/** Increase the indentation of the output code produced
	 *  on the specified builder.
	 *  @param The builder to indent.
	 */
	protected def indent(StringBuilder builder) {
		var prefix = indentation.get(builder)
		if (prefix === null) {
			prefix = ""
		}
		val buffer = new StringBuffer(prefix)
		for (var i = 0; i < 4; i++) {
			buffer.append(' ');
		}
		indentation.put(builder, buffer.toString)
	}
	
	/** Append the specified text plus a final newline to the current
	 *  code buffer.
	 *  @param text The text to append.
	 */
	protected def pr(Object text) {
		pr(code, text)
	}
	
	/** Append the specified text plus a final newline to the specified
	 *  code buffer.
	 *  @param builder The code buffer.
	 *  @param text The text to append.
	 */
	protected def pr(StringBuilder builder, Object text) {
		// Handle multi-line text.
		var string = text.toString
		var indent = indentation.get(builder)
		if (indent === null) {
			indent = ""
		}
		if (string.contains("\n")) {
			// Replace all tabs with four spaces.
			string = string.replaceAll("\t", "    ")
			// Use two passes, first to find the minimum leading white space
			// in each line of the source text.
			var split = string.split("\n")
			var offset = Integer.MAX_VALUE
			var firstLine = true
			for (line : split) {
				// Skip the first line, which has white space stripped.
				if (firstLine) {
					firstLine = false
				} else {
					var numLeadingSpaces = line.indexOf(line.trim());
					if (numLeadingSpaces < offset) {
						offset = numLeadingSpaces
					}
				}
			}
			// Now make a pass for each line, replacing the offset leading
			// spaces with the current indentation.
			firstLine = true
			for (line : split) {
				builder.append(indent)
				// Do not trim the first line
				if (firstLine) {
					builder.append(line)
					firstLine = false
				} else {
					builder.append(line.substring(offset))
				}
				builder.append("\n")
			}
		} else {
			builder.append(indent)
			builder.append(text)
			builder.append("\n")
		}
	}
	
	/** If the argument starts with '{=', then remove it and the last two characters.
	 *  @return The body without the code delimiter or the unmodified argument if it
	 *   is not delimited.
	 */
	protected def String removeCodeDelimiter(String code) {
		if (code === null) {
			""
		} else if (code.startsWith("{=")) {
            code.substring(2, code.length - 2).trim();
        } else {
        	code
        }
	}
	
	/** Report an error on the specified parse tree object.
	 *  @param object The parse tree object.
	 *  @param message The error message.
	 */
	protected def reportError(EObject object, String message) {
		// FIXME: All calls to this should also be checked by the validator (See LinguaFrancaValidator.xtend).
        // In case we are using a command-line tool, we report the line number.
        // The caller should not throw an exception so compilation can continue.
        var node = NodeModelUtils.getNode(object)
        System.err.println("ERROR: Line "
            		+ node.getStartLine()
               		+ ": "
            		+ message)
        // Return a string that can be inserted into the generated code.
        "[[ERROR: " + message + "]]"
	}

	/** Report a warning on the specified parse tree object.
	 *  @param object The parse tree object.
	 *  @param message The error message.
	 */
	protected def reportWarning(EObject object, String message) {
		// FIXME: All calls to this should also be checked by the validator (See LinguaFrancaValidator.xtend).
        // In case we are using a command-line tool, we report the line number.
        // The caller should not throw an exception so compilation can continue.
        var node = NodeModelUtils.getNode(object)
        System.err.println("WARNING: Line "
            		+ node.getStartLine()
               		+ ": "
            		+ message)
        // Return an empty string that can be inserted into the generated code.
        ""
	}

	/** Reduce the indentation by one level for generated code
	 *  in the default code buffer.
	 */
	protected def unindent() {
		unindent(code)
	}
	
	/** Reduce the indentation by one level for generated code
	 *  in the specified code buffer.
	 */
	protected def unindent(StringBuilder builder) {
		var indent = indentation.get(builder)
		if (indent !== null) {
			val end = indent.length - 4;
			if (end < 0) {
				indent = ""
			} else {
				indent = indent.substring(0, end)
			}
			indentation.put(builder, indent)
		}
	}
	
	/** Given a representation of time that may possibly include units,
	 *  return a string for the same amount of time
	 *  in terms of the specified baseUnit. If the two units are the
	 *  same, or if no time unit is given, return the number unmodified.
	 *  @param time The source time.
	 *  @param baseUnit The target unit.
	 */
	protected def unitAdjustment(Time time, String baseUnit) {
		if (time === null || time.time === null) {
			return '0'
		}
		if (time.unit === null || baseUnit.equals(time.unit)) {
			return time.time
		}
		try {
			var nf = NumberFormat.getInstance();
			// The following will try to return a Long, and if that fails, will return a Double.
			var parsed = nf.parse(time.time)
			var unitScale = timeUnitsToNs.get(time.unit)
			if (unitScale === null) {
				// Invalid unit specification.
				return reportError(time, "Invalid unit '" + time.unit + "'. Should be one of: " + timeUnitsToNs.keySet)
			}
			var baseScale = timeUnitsToNs.get(baseUnit)
			if (baseScale === null) {
				// This is an error in the target code generator, not in the source code.
				throw new Exception("Invalid target base unit: " + baseUnit + ". Should be one of: " + timeUnitsToNs.keySet)				
			}
			// Handle Double and Long separately.
			if (parsed instanceof Long) {
				// First convert the number to units of nanoseconds.
				var numberInNs = parsed.longValue() * unitScale
				// Then convert to baseUnits.
				var result = numberInNs / baseScale
				return result.toString()
			} else {
				// Assume its is a Double.
				// First convert the number to units of nanoseconds.
				var numberInNs = parsed.doubleValue() * unitScale
				// Then convert to baseUnits.
				var result = numberInNs / baseScale
				return result.toString()
			}
		} catch (ParseException ex) {
			return reportError(time, "Failed to parse number '" + time.time + "'. " + ex)
		}
	}
}
