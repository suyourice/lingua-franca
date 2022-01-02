/* Generator for Uclid models. */

/*************
Copyright (c) 2021, The University of California at Berkeley.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
***************/

package org.lflang.generator

import java.nio.file.Path
import java.nio.file.Paths
import java.util.ArrayList
import java.util.HashMap
import java.util.LinkedHashMap
import java.util.LinkedList
import java.util.List
import java.util.Map
import java.util.Set
import org.eclipse.emf.ecore.resource.Resource
import org.eclipse.emf.ecore.EObject
import org.eclipse.xtext.generator.IFileSystemAccess2
import org.eclipse.xtext.generator.IGeneratorContext
import org.eclipse.xtext.nodemodel.util.NodeModelUtils
import org.lflang.generator.PortInstance
import org.lflang.generator.JavaGeneratorUtils
import org.lflang.lf.Action
import org.lflang.lf.Attribute
import org.lflang.lf.Code
import org.lflang.lf.VarRef
import org.lflang.lf.StateVar
import org.lflang.CausalityInfo
import org.lflang.ErrorReporter
import org.lflang.FileConfig
import org.lflang.Target

import static extension org.lflang.ASTUtils.*

/**
 * Generator for Uclid models.
 * 
 * @author Shaokai Lin {@literal <shaokai@eecs.berkeley.edu>}
 */
class UclidGenerator extends GeneratorBase {
    
    ////////////////////////////////////////////
    //// Public variables
    
    // The output directory where the model is stored
    Path outputDir
    
    // The reaction graph upon which the causality graph is built
    var ReactionInstanceGraph reactionGraph

    // Data structures for storing info about the runtime instances
    var Set<ReactionInstance>                   reactions
    var Set<PortInstance>                       ports
    var List<Pair<ReactorInstance, StateVar>>   stateVars
        = new ArrayList<Pair<ReactorInstance, StateVar>>

    // The causality graph captures counterfactual causality
    // relations between adjacent reactions.
    var CausalityGraph causalityGraph

    // Trace length
    int traceLength

    // Data structures for storing properties
    var List<String>                        properties  = new ArrayList
    var HashMap<String, List<Attribute>>    propertyMap = new LinkedHashMap
    var HashMap<String, List<Attribute>>    auxInvMap   = new LinkedHashMap
    var HashMap<String, Attribute>          boundMap    = new LinkedHashMap
    
    // Constructor
    new(FileConfig fileConfig, ErrorReporter errorReporter) {
        super(fileConfig, errorReporter)
    }
    
    ////////////////////////////////////////////
    //// Private variables
    
    override void doGenerate(Resource resource, IFileSystemAccess2 fsa,
        IGeneratorContext context) {
        
        // The following generates code needed by all the reactors.
        super.doGenerate(resource, fsa, context)

        if (this.targetConfig.verification !== null) {
            if (this.targetConfig.verification.engine !== null) {
                switch (this.targetConfig.verification.engine) {
                    case "uclid": {
                        generateModel(resource, fsa, context)
                    }
                    default: {
                        throw new RuntimeException("The specified engine is not supported.")
                    }
                }
            }
        } else {
            // If verification flag is not specified, exit the generator.
            return
        }
    }

    def void generateModel(Resource resource, IFileSystemAccess2 fsa,
        IGeneratorContext context) {

        // FIXME: Does this handle the federated reactor in case of federated execution?    
        for (federate : federates) {
            // Build the instantiation tree if a main reactor is present.
            if (this.mainDef !== null) {
                if (this.main === null) {
                    // Recursively build instances. This is done once because
                    // it is the same for all federates.
                    this.main = new ReactorInstance(
                        mainDef.reactorClass.toDefinition,
                        this.errorReporter
                    )
                }   
            } else {
                println("WARNING: No main reactor detected. No model is generated.")
                return
            }
        }  

        // Build reaction instance graph and causality graph
        populateGraphsAndLists()
        
        // Create the "src-gen" directory if it doesn't yet exist.
        var dir = fileConfig.getSrcGenPath.toFile
        if (!dir.exists()) dir.mkdirs()
        
        // Create the "model" directory if it doesn't yet exist.
        dir = fileConfig.getSrcGenPath.resolve("model").toFile
        if (!dir.exists()) dir.mkdirs()
        outputDir = Paths.get(dir.getAbsolutePath)
        println("The models will be located in: " + outputDir)

        // Identify properties and generate a model for each property.
        var mainAttr = this.main.reactorDefinition.getAttributes
        if (mainAttr.length != 0) {
            for (attr : mainAttr) {
                // Extract the property name.
                // Add to the list if it doesn't exist.
                var property = attr.getAttrParms.get(0).replaceAll("^\"|\"$", "")
                if (!this.properties.contains(property)) {
                    this.properties.add(property)
                }
                // Check the type of the attribute,
                // then populate the hashmap.
                switch attr.getAttrName.toString {
                    case 'property' : {
                        if (this.propertyMap.get(property) === null) {
                            this.propertyMap.put(property, new LinkedList)
                        }
                        this.propertyMap.get(property).add(attr)
                    }
                    case 'aux' : {
                        if (this.auxInvMap.get(property) === null) {
                            this.auxInvMap.put(property, new LinkedList)
                        }
                        this.auxInvMap.get(property).add(attr)
                    }
                    case 'bound' : {
                        if (this.boundMap.get(property) === null) {
                            this.boundMap.put(property, attr)
                        } else {
                            println("WARNING: Redundant bound specification for the same property.")
                        }
                    }
                }
            }
        } else {
            println("WARNING: No main reactor attribute detected. No model is generated.")
            return
        }

        // Generate a Uclid model for each property.
        for (property : this.properties) {
            printModelToFile(property)
        }

        // Generate runner script
        code = new StringBuilder()
        var filename = outputDir.resolve("run.sh").toString
        generateRunnerScript()
        JavaGeneratorUtils.writeSourceCodeToFile(getCode, filename)
    }

    /**
     * @brief Recursively add state variables to the stateVars list.
     * @param reactor A reactor instance from which the search begins.
     */
    private def void populateStateVars(ReactorInstance reactor) {
        // Set trace length
        this.traceLength = targetConfig.verification.steps
        
        var defn = reactor.reactorDefinition
        var stateVars = defn.getStateVars

        // Prefix state vars with reactor name
        // and add them to the list
        for (s : stateVars) {
            this.stateVars.add(new Pair(reactor, s))
        }

        // Populate state variables recursively
        for (child : reactor.children) {
            populateStateVars(child)
        }
    }

    /**
     * Populate the data structures.
     */
    private def populateGraphsAndLists() {
        this.reactionGraph = new ReactionInstanceGraph(this.main)
        this.causalityGraph = new CausalityGraph(this.main, this.reactionGraph)
        this.reactions = this.reactionGraph.nodes

        // Ports are populated during the construction of the causality graph
        this.ports = this.causalityGraph.ports
        // Populate state variables by traversing reactor instances
        populateStateVars(this.main)
    }
    
    /**
     * Generate the Uclid model and a runner script.
     */
    protected def printModelToFile(String property) {     
        // Generate main.ucl and print to file
        code = new StringBuilder()
        var filename = outputDir.resolve("property_" + property + ".ucl").toString
        generateMain(property)
        JavaGeneratorUtils.writeSourceCodeToFile(getCode, filename)
    }
    
    protected def generateMain(String property) {
        pr('''
        /*******************************
         * Auto-generated UCLID5 model *
         ******************************/
        ''')
        
        // Start the main module
        pr('''
        module main {
        ''')
        newline()
        indent()
        
        // Print timing semantics
        pr_timing_semantics()

        // Reaction IDs and state variables
        pr_rxn_ids_and_state_vars()
        
        // Trace definition
        pr_trace_def_and_helper_macros()
        
        // Topology
        pr_topological_abstraction()
        
        // Reactor semantics
        pr_reactor_semantics()

        // Connections
        pr_connections()

        // Topology
        pr_program_topology()

        // Initial Condition
        pr_initial_condition()

        // Reactor contracts
        pr_reactor_contracts()

        // Reaction contracts
        pr_reaction_contracts()

        // K-induction
        var conjunctList    = this.propertyMap.get(property)
        var auxInvList      = this.auxInvMap.get(property)
        var bound           = this.boundMap.get(property)
        pr_k_induction(property, conjunctList, auxInvList, bound)

        // Control block
        pr_control_block()
        
        unindent()
        pr('}')
    }

    def pr_timing_semantics() {
        // [static] definition of time and timing-related operations
        pr('''
        /*******************************
         * Time and Related Operations *
         ******************************/
        type timestamp_t = integer;                     // The unit is nanoseconds
        type microstep_t = integer;
        type tag_t = {
            timestamp_t,
            microstep_t
        };
        type interval_t  = tag_t;
        
        // Projection macros
        define pi1(t : tag_t) : timestamp_t = t._1;     // Get timestamp from tag
        define pi2(t : tag_t) : microstep_t = t._2;     // Get microstep from tag
        
        // Interval constructor
        define zero() : interval_t
        = {0, 0};
        define startup() : interval_t
        = zero();
        define mstep() : interval_t
        = {0, 1};
        define nsec(t : integer) : interval_t
        = {t, 0};
        define usec(t : integer) : interval_t
        = {t * 1000, 0};
        define msec(t : integer) : interval_t
        = {t * 1000000, 0};
        define sec(t : integer) : interval_t
        = {t * 1000000000, 0};
        define inf() : interval_t
        = {-1, 0};
        
        // Helper function
        define isInf(i : interval_t) : boolean
        = pi1(i) < 0;
        
        // Tag comparison
        define tag_later(t1 : tag_t, t2 : tag_t) : boolean
        = pi1(t1) > pi1(t2)
            || (pi1(t1) == pi1(t2) && pi2(t1) > pi2(t2))
            || (isInf(t1) && !isInf(t2));
        
        define tag_same(t1 : tag_t, t2 : tag_t) : boolean
        = t1 == t2;
        
        define tag_earlier(t1 : tag_t, t2 : tag_t) : boolean
        = pi1(t1) < pi1(t2)
            || (pi1(t1) == pi1(t2) && pi2(t1) < pi2(t2))
            || (!isInf(t1) && isInf(t2));
        
        // Tag algebra
        define tag_schedule(t : tag_t, i : interval_t) : tag_t
        = if (!isInf(t) && pi1(i) == 0 && !isInf(i))
            then { pi1(t), pi2(t) + 1 } // microstep delay
            else ( if (!isInf(t) && pi1(i) > 0 && !isInf(i))
                then { pi1(t) + pi1(i), 0 }
                else inf());
        
        define tag_delay(t : tag_t, i : interval_t) : tag_t
        = if (!isInf(t) && !isInf(i))
            then { pi1(t) + pi1(i), pi2(t) + pi2(i) }
            else inf();
        
        // Only consider timestamp for now.
        define tag_diff(t1, t2: tag_t) : interval_t
        = if (!isInf(t1) && !isInf(t2))
            then { pi1(t1) - pi1(t2), pi2(t1) - pi2(t2) }
            else inf();
        ''')
        newline()
    }

    // FIXME: generate custom code.
    def pr_rxn_ids_and_state_vars() {
        // [dynamic] Encode the components and
        // the logical delays present in a reactor system.
        pr('''
        /**********************************
         * Reaction IDs & State Variables *
         *********************************/
        
        //////////////////////////
        // Application Specific
        ''')
        
        /* Enumerate over all reactions */
        pr('''
        // Reaction ids
        type rxn_t = enum {
        ''')
        indent()
        for (rxn : reactions) {
            // Print a list of reaction IDs.
            // Add a comma if not last.
            pr(rxn.getFullNameWithJoiner('_') + ',')
        }
        pr('NULL')
        unindent()
        pr('};')

        /* State variables and ports */
        // FIXME: expand to data types other than integer
        pr('''
        type state_t = {
        ''')
        indent()
        if (this.ports.size + this.stateVars.size > 0) {
            var i = 0;
            for (v : this.stateVars) {
                pr(
                    "integer"
                    + ((this.ports.size == 0 && i++ == this.stateVars.size - 1) ? "" : ",")
                    + " \t// " + stateVarFullNameWithJoiner(v, ".")
                )
            }
            i = 0;
            for (p : this.ports) {
                pr(
                    "integer"
                    + ((i++ == ports.size - 1) ? "" : ",")
                    + " \t// " + p.getFullName
                )
            }
        } else {
            pr('''
            // There are no ports or state variables.
            // Insert a dummy integer to make the model compile.
            integer
            ''')
        }
        unindent()
        pr('};')
        pr('''
        // State variable projection macros
        ''')
        var i = 0;
        for (v : this.stateVars) {
            pr('''
            define «stateVarFullNameWithJoiner(v, "_")»(s : state_t) : integer = s._«i+1»;
            ''')
            i++;
        }
        for (p : this.ports) {
            pr('''
            define «p.getFullNameWithJoiner('_')»(s : state_t) : integer = s._«i+1»;
            ''')
            i++;
        }
        newline()
        pr('//////////////////////////')
        newline()
    }

    def pr_trace_def_and_helper_macros() {
        pr('''
        /********************
         * Trace Definition *
         *******************/
        const START : integer = 0;
        const END : integer = «traceLength-1»;
        
        define in_range(num : integer) : boolean
        = num >= START && num <= END;
        
        type step_t = integer;
        type event_t = { rxn_t, tag_t, state_t };
        ''')
        pr('')
        pr('''
        // Create a bounded trace of «traceLength» events.
        ''')
        pr("type trace_t = {")
        indent()
        for (var i = 0; i < traceLength; i++) {
            pr("event_t" +
                (i == traceLength - 1 ? "" : ","))
        }
        unindent()
        pr('};')
        newline()

        pr('''
        // mark the start of the trace.
        var start : timestamp_t;
        
        // declare the trace
        var trace : trace_t;

        /*****************
         * Helper Macros *
         ****************/
        ''')

        // Generate a getter for the finite trace.
        var String integerInit
        var varSize = this.stateVars.size + this.ports.size
        if (varSize > 0) {
            integerInit = "0, ".repeat(varSize)
            integerInit = integerInit.substring(0, integerInit.length - 2)
        } else {
            integerInit = "0"
        }
        pr('''
        // helper macro that returns an element based on index
        define get(tr : trace_t, i : step_t) : event_t =
        ''')
        for (var j = 0; j < traceLength; j++) {
            pr('''
            if (i == «j») then tr._«j+1» else (
            ''')
        } 
        pr('''
        { NULL, inf(), { «integerInit» } } «")".repeat(traceLength)»;
        ''')
        newline()
        pr('''
        define elem(i : step_t) : event_t
        = get(trace, i);
        
        // projection macros
        define rxn      (i : step_t) : rxn_t    = elem(i)._1;
        define g        (i : step_t) : tag_t    = elem(i)._2;
        define s        (i : step_t) : state_t  = elem(i)._3;
        define isNULL   (i : step_t) : boolean  = rxn(i) == NULL;
        ''')
        newline()
    }
    
    def pr_topological_abstraction() {
        pr('''
        /***************************
         * Topological Abstraction *
         ***************************/
        ''')

        // Generate the delay macro
        pr('''
        // Delay macro
        define delay(r1, r2 : rxn_t) : interval_t =
        ''')
        indent()
        var i = 0
        for (Map.Entry<Pair<ReactionInstance, ReactionInstance>, CausalityInfo> entry :
            causalityGraph.causality.entrySet.filter[ !it.getValue.type.equals("startup") && !it.getValue.type.equals("timer") ]) {
            pr('''
            if (r1 == «entry.getKey.getKey.getFullNameWithJoiner('_')» && r2 == «entry.getKey.getValue.getFullNameWithJoiner('_')») then nsec(«entry.getValue.delay») else (
            ''')
            i++;
        }
        pr('inf()')
        var closingBrackets = ')'.repeat(i)
        pr('''
        «closingBrackets»;
        ''')
        unindent()
        newline()

        // Non-federated "happened-before"
        // FIXME: Need to compute the transitive closure.
        // Happened-before relation defined for a local reactor.
        // Used to preserve trace ordering.
        pr('''
        // Non-federated "happened-before"
        define hb(e1, e2 : event_t) : boolean
        = tag_earlier(e1._2, e2._2)
        ''')
        indent()
        indent()
        i = 0
        var str = '''
        || (tag_same(e1._2, e2._2) && (
        '''
        for (Map.Entry<Pair<ReactionInstance, ReactionInstance>, CausalityInfo> entry :
            causalityGraph.causality.entrySet.filter[ !it.getValue.type.equals("startup") && !it.getValue.type.equals("timer") ]
        ) {
            var upstream    = entry.getKey.getKey.getFullNameWithJoiner('_')
            var downstream  = entry.getKey.getValue.getFullNameWithJoiner('_')
            str += '''
            «i == 0 ? "" : "|| "»(e1._1 == «upstream» && e2._1 == «downstream»)
            '''
            i++;
        }
        // If there are no counterfactual reaction pairs,
        // simply put a "true" there.
        if (i != 0) {
            pr(str)
            pr('));')
        }
        else {
            pr(';')
        }
        unindent()
        unindent()
        newline() 

        pr('''
        define startup_triggers(n : rxn_t) : boolean
        = // if startup is within frame, put the events in the trace.
            ((start == 0) ==> (exists (i : integer) :: in_range(i)
                && rxn(i) == n && tag_same(g(i), zero())))
            // Can ONLY be triggered at (0,0).
            // FIXME: this case seems to be taken care of by an axiom below.
            && !(exists (j : integer) :: in_range(j) && rxn(j) == n
                && !tag_same(g(j), zero()));

        // Note: The current formulation of "triggers" precludes
        //       partial reaction triggering chain.
        // This includes the possibility that upstream does NOT output.
        define triggers_via_logical_action
            (upstream, downstream : rxn_t, delay : interval_t) : boolean
        = forall (i : integer) :: in_range(i)
            ==> (rxn(i) == downstream 
                ==> (exists (j : integer) :: in_range(j)
                    && rxn(j) == upstream 
                    && g(i) == tag_schedule(g(j), delay)));

        define triggers_via_logical_connection
            (upstream, downstream : rxn_t, delay : interval_t) : boolean
        = forall (i : integer) :: in_range(i)
            ==> (rxn(i) == downstream 
                ==> (exists (j : integer) :: in_range(j)
                    && rxn(j) == upstream 
                    && g(i) == tag_delay(g(j), delay)));

        //// Encoding the behavior of timers
        define is_multiple_of(a, b : integer) : boolean
        = exists (c : integer) :: b * c == a;
        
        define is_closest_starting_point(t : tag_t, period, offset : integer) : boolean
        = (exists (c : integer) :: (period * c) + offset == pi1(t)
            // Tick at the next valid instant.
            && (period * (c - 1) + offset) < start)     
            // Timer always has mstep of 0.
            && pi2(t) == 0;

        // Can directly use index as HB since this only applies to events
        // on the same federate.
        define is_latest_invocation_in_same_fed_wrt(a, b : integer) : boolean
        = !(exists (c : integer) :: in_range(c)
            && rxn(c) == rxn(a) && a < c && c < b);
        
        define timer_triggers(_rxn : rxn_t, offset, period : integer) : boolean =
            // 1. If the initial event is within frame, show it.
            (exists (i : integer) :: in_range(i)
            && rxn(i) == _rxn
            && is_closest_starting_point(g(i), period, offset))
            // 2. The SPACING between two consecutive timer firings is the period.
            // FIXME: Is the use of two in_range() here appropriate?
            // Shaokai: Seems so to me, since the first state is not actually constrained.
            && (forall (i, j : integer) :: (in_range(i) && in_range(j) && i < j
                && rxn(i) == _rxn && rxn(j) == _rxn
                // ...and there does not exist a 3rd invocation in between
                && !(exists (k : integer) :: rxn(k) == _rxn && i < k && k < j))
                    ==> g(j) == tag_schedule(g(i), {period, 0}))
            // 3. There does not exist other events in the same federate that 
            // differ by the last timer invocation by g(last_timer) + period.
            // In other words, this axiom ensures a timer fires when it needs to.
            //
            // a := index of the offending event that occupy the spot of a timer tick.
            // b := index of non-timer event on the same federate
            // both in_range's are needed due to !(exists), which turns into a forall.
            && !(exists (b, a : integer) :: in_range(a) && in_range(b)
                && rxn(b) != _rxn
                // && _id_same_fed(elem(b), {_id, zero()})
                && rxn(a) == _rxn
                && (is_latest_invocation_in_same_fed_wrt(a, b)
                    && tag_later(g(b), tag_schedule(g(a), {period, 0}))));
        ''')
        newline()
    }
    
    // Encode reactor semantics
    def pr_reactor_semantics() {
        pr('''
        /*********************
         * Reactor Semantics *
         *********************/
        /** transition relation **/
        // transition relation constrains future states
        // based on previous states.

        // Events are ordered by "happened-before" relation.
        axiom(forall (i, j : integer) :: (in_range(i) && in_range(j))
            ==> (hb(elem(i), elem(j)) ==> i < j));
        
        // the same event can only trigger once in a logical instant
        axiom(forall (i, j : integer) :: (in_range(i) && in_range(j))
            ==> ((rxn(i) == rxn(j) && i != j)
                ==> !tag_same(g(i), g(j))));

        // Tags should be positive
        axiom(forall (i : integer) :: (i > START && i <= END)
            ==> pi1(g(i)) >= 0);

        // Microsteps should be positive
        axiom(forall (i : integer) :: (i > START && i <= END)
            ==> pi2(g(i)) >= 0);

        // Begin the frame at the start time specified.
        define start_frame(i : step_t) : boolean =
            (tag_same(g(i), {start, 0}) || tag_later(g(i), {start, 0}));
        axiom(forall (i : integer) :: (i > START && i <= END)
            ==> start_frame(i));

        // NULL events should appear in the suffix, except for START.
        axiom(forall (j : integer) :: (j > START && j <= END) ==> (
            (rxn(j)) != NULL) ==> 
                (forall (i : integer) :: (i > START && i < j) ==> (rxn(i) != NULL)));

        // When a NULL event occurs, the state stays the same.
        axiom(forall (j : integer) :: (j > START && j <= END) ==> (
            (rxn(j) == NULL) ==> (s(j) == s(j-1))
        ));
        ''')
        newline()
    }

    // Connections
    def pr_connections() {
        pr('''
        /***************
         * Connections *
         ***************/
        ''')
        newline()
        for (Map.Entry<Pair<ReactionInstance, ReactionInstance>, CausalityInfo> entry :
            causalityGraph.causality.entrySet()) {
            // Check if two reactions are linked by a connection
            // if so, the output port and the input port should
            // hold the same value.
            if (entry.getValue.type.equals("connection")) {
                var upstreamRxn    = entry.getKey.getKey.getFullNameWithJoiner('_')
                var upstreamPort   = entry.getValue.upstreamPort.getFullNameWithJoiner('_')
                var downstreamPort = entry.getValue.downstreamPort.getFullNameWithJoiner('_')
                pr('''
                // «upstreamPort» -> «downstreamPort» 
                axiom(forall (i : integer) :: (i > START && i <= END)
                    ==> (
                        (rxn(i) == «upstreamRxn» ==> «downstreamPort»(s(i)) == «upstreamPort»(s(i)))
                        && (rxn(i) != «upstreamRxn» ==> «downstreamPort»(s(i)) == «downstreamPort»(s(i - 1)))
                    ));
                ''')
                newline()
            }
        }
    }

    // Topology
    def pr_program_topology() {
        pr('''
        /********************
         * Program Topology *
         ********************/         
        ''')
        newline()
        for (Map.Entry<Pair<ReactionInstance, ReactionInstance>, CausalityInfo> entry :
            causalityGraph.causality.entrySet()) {
            var upstreamRxn     = entry.getKey.getKey
            var downstreamRxn   = entry.getKey.getValue
            var upstreamName    = upstreamRxn.getFullName
            var downstreamName  = downstreamRxn?.getFullName
            var upstreamId      = upstreamRxn.getFullNameWithJoiner('_')
            var downstreamId    = downstreamRxn?.getFullNameWithJoiner('_')
            var conn            = entry.getValue
            // Upstream triggers downstream via a logical connection.
            if (conn.type.equals("startup")) {
                pr('''
                // «upstreamName» is triggered by startup.
                axiom(startup_triggers(«upstreamId»));
                ''')
            }
            else if (conn.type.equals("timer")) {
                var offset = (conn.triggerInstance as TimerInstance).getOffset.toNanoSeconds
                var period = (conn.triggerInstance as TimerInstance).getPeriod.toNanoSeconds
                pr('''
                // «upstreamName» is triggered by timer.
                axiom(timer_triggers(«upstreamId», «offset», «period»));
                ''')
            }
            else if (conn.type.equals("connection") && !conn.isPhysical) {
                pr('''
                // «upstreamName» triggers «downstreamName» via a logical connection.
                axiom(triggers_via_logical_connection(«upstreamId», «downstreamId»,
                    delay(«upstreamId», «downstreamId»)));
                ''')
            }
            // Upstream triggers downstream via a physical connection.
            else if (conn.type.equals("connection") && conn.isPhysical) {
                pr('''
                // «upstreamName» triggers «downstreamName» via a physical connection.
                axiom(triggers_via_physical_connection(«upstreamId», «downstreamId»));
                ''')
            }
            // Upstream triggers downstream via a logical action.
            else if (conn.type.equals("action") && !conn.isPhysical) {
                pr('''
                // «upstreamName» triggers «downstreamName» via a logical action.
                axiom(triggers_via_logical_action(«upstreamId», «downstreamId»,
                    delay(«upstreamId», «downstreamId»)));
                ''')
            }
            // Upstream triggers downstream via a physical action.
            else if (conn.type.equals("action") && conn.isPhysical) {
                pr('''
                // «upstreamName» triggers «downstreamName» via a physical action.
                axiom(triggers_via_physical_action(«upstreamId», «downstreamId»));
                ''')
            }
            else {
                throw new UnsupportedOperationException("Invalid topology.")
            }
            newline()
        }
    }

    // Initial Condition
    def pr_initial_condition() {
        pr('''
        /*********************
         * Initial Condition *
         *********************/
        // FIXME: add template
        define initial_condition() : boolean
        = start == 0
            && rxn(0) == NULL
            && g(0) == {0, 0}
        ''')
        indent()
        for (v : this.stateVars) {
            pr('''
            && «stateVarFullNameWithJoiner(v, "_")»(s(0)) == 0
            ''')
        }
        for (p : this.ports) {
            pr('''
            && «p.getFullNameWithJoiner('_')»(s(0)) == 0
            ''')
        }
        pr(';')
        newline()
        unindent()
    }

    def pr_reactor_contracts() {
        pr('''
        /*********************
         * Reactor Contracts *
         *********************/
        ''')
        newline()
        for (r : this.reactors.filter[!it.main]) {
            var reactorAttr = r.getAttributes
            if (reactorAttr.length != 0) {
                for (attr : reactorAttr) {
                    if (attr.getAttrName.toString.equals("inv")) {
                        // Extract the invariant out of the attribute.
                        var inv = attr.getAttrParms.get(0).replaceAll("^\"|\"$", "")
                        // Print line number
                        prSourceLineNumber(attr)
                        pr('''
                        /* Input/output relations for «r.getName» */
                        axiom(forall (i : integer) :: (i > START && i <= END) ==>
                        ''')
                        indent()
                        pr(inv)
                        unindent()
                        pr('''
                        ));
                        ''')
                        newline()
                    }
                }
            }
        }
    }

    // Reaction contracts
    def pr_reaction_contracts() {
        pr('''
        /**********************
         * Reaction Contracts *
         **********************/
        ''')
        newline()
        for (rxn : this.reactions) {
            pr('''
            /* Pre/post conditions for «rxn.getFullName» */
            axiom(forall (i : integer) :: (i > START && i <= END) ==>
                (rxn(i) == «rxn.getFullNameWithJoiner('_')» ==> ( true
            ''')
            indent()
            var attrList = rxn.definition.getAttributes
            if (attrList.length != 0) {
                for (attr : attrList) {
                    if (attr.getAttrName.toString.equals("inv")) {
                        // Extract the invariant out of the attribute.
                        var inv = attr.getAttrParms.get(0).replaceAll("^\"|\"$", "")
                        // Print line number
                        prSourceLineNumber(attr)
                        pr('''
                        && «inv»
                        ''')
                    }
                }
            }
            unindent()
            pr('''
            )));
            ''')
            newline()
        }
    }

    // Properties
    def pr_k_induction(String propertyName, List<Attribute> conjunctList, List<Attribute> auxInvList, Attribute bound) {
        // Set the property bound, and set k to the maximum allowed by the trace.
        pr('''
        /************
         * Property *
         ************/
        ''')
        // Extract the property bound out of the attribute.
        var boundValue = Integer.parseInt(bound.getAttrParms.get(1))
        // Print line number
        prSourceLineNumber(bound)
        pr('''
        const b : integer = «boundValue»; // The property bound
        
        // max_k = trace end index - property bound - one consecution step
        // Note: k is bounded by max_km which depends on the trace length.
        //       The selection of k does not directly depend on max_k.
        define max_k() : integer = END - b - 1; 
        define k() : integer = max_k();
        ''')
        newline()

        // Print the property in the form of a conjunction.
        pr('''
        // The FOL property translated from user-defined LTL property
        define P(i : step_t) : boolean =
            true
        ''')
        indent()
        for (conjunct : conjunctList) {
            // Extract the invariant out of the attribute.
            var formula = conjunct.getAttrParms.get(1).replaceAll("^\"|\"$", "")
            // Print line number
            prSourceLineNumber(conjunct)
            pr('''
            && «formula»
            ''')
        }
        unindent()
        pr(";")
        newline()

        // Print auxiliary invariants.
        pr('''
        // Auxiliary invariant
        define aux_inv(i : integer) : boolean =
            // Add this here, so that in the consecution step,
            // the first state respects start.
            start_frame(i)
        ''');
        indent()
        for (auxInv : auxInvList) {
            // Extract the invariant out of the attribute.
            var formula = auxInv.getAttrParms.get(1).replaceAll("^\"|\"$", "")
            // Print line number
            prSourceLineNumber(auxInv)
            pr('''
            && «formula»
            ''')
        }
        unindent()
        pr(";")
        newline()

        // Compose the property and the auxiliary invariants.
        pr('''
        // Strengthened property
        define Q(i : step_t) : boolean =
            P(i) && aux_inv(i);

        // Helper macro for temporal induction
        define Globally_Q(start, end : step_t) : boolean =
            (forall (i : integer) :: (i >= start && i <= end) ==> Q(i));
        ''')
        newline()

        // Print k-induction formulae.
        pr('''
        /***************
         * K-Induction *
         ***************/
        // Initiation
        property initiation_«propertyName» : initial_condition() ==>
            Globally_Q(0, k());

        // Consecution
        property consecution_«propertyName» : 
            Globally_Q(0, k()) ==> Q(k()+1);

        // Make sure k is valid.
        property N_is_valid_«propertyName» :
            k() <= max_k();
        ''')
        newline()
    }

    // Control block
    def pr_control_block() {
        pr('''
        control {
            v = bmc(0);
            check;
            print_results;
            v.print_cex;
        }
        ''')
    }
    
    protected def generateRunnerScript() {
        pr('''
        #!/bin/bash
        set -e # Terminate on error
        
        echo '*** Setting up smt directory'
        rm -rf ./smt/ && mkdir -p smt
        
        echo '*** Generating SMT files from UCLID5'
        uclid -g "smt/output" $1
        
        echo '*** Append (get-model) to each file'
        ls smt | xargs -I {} bash -c 'echo "(get-model)" >> smt/{}'
        
        echo '*** Running Z3'
        ls smt | xargs -I {} bash -c 'echo "Checking {}" && z3 -T:120 ./smt/{}'
        ''')
    }
    
    /////////////////////////////////////////////////
    //// Helper functions

    protected def String stateVarFullNameWithJoiner(Pair<ReactorInstance, StateVar> s, String joiner) {
        if (joiner.equals("_"))
            return (s.getKey.getFullName + joiner + s.getValue.name).replace(".", "_")
        else return (s.getKey.getFullName + joiner + s.getValue.name)
    }

    protected def newline() {
        pr('')
    }

    /**
     * Leave a marker in the generated code that indicates the original line
     * number in the LF source.
     * @param eObject The node.
     */
    override prSourceLineNumber(EObject eObject) {
        if (eObject instanceof Code) {
            pr(code, '''//// Line «NodeModelUtils.getNode(eObject).startLine +1» in the LF program''')
        } else {
            pr(code, '''//// Line «NodeModelUtils.getNode(eObject).startLine» in the LF program''')
        }
    }
    
    /////////////////////////////////////////////////
    //// Functions from generatorBase
    
    override getTarget() {
        return Target.C // FIXME: How to make this target independent? Target.ALL does not work.
    }

    override supportsGenerics() {
        return false
    }

    // Intentionally preserve delays.
    override transformDelays() {
        return
    }

    override generateDelayBody(Action action, VarRef port) {
        throw new UnsupportedOperationException("TODO: auto-generated method stub")
    }
    
    override generateForwardBody(Action action, VarRef port) {
        throw new UnsupportedOperationException("TODO: auto-generated method stub")
    }
    
    override generateDelayGeneric() {
        throw new UnsupportedOperationException("TODO: auto-generated method stub")
    }
    
    override getTargetTimeType() {
        throw new UnsupportedOperationException("TODO: auto-generated method stub")
    }
    
    override getTargetTagType() {
        throw new UnsupportedOperationException("TODO: auto-generated method stub")
    }
    
    override getTargetUndefinedType() {
        throw new UnsupportedOperationException("TODO: auto-generated method stub")
    }
    
    override getTargetFixedSizeListType(String baseType, int size) {
        throw new UnsupportedOperationException("TODO: auto-generated method stub")
    }

    override getTargetVariableSizeListType(String baseType) {
        throw new UnsupportedOperationException("TODO: auto-generated method stub")
    }
 
}