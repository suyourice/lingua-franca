package org.lflang.generator.python;

import java.util.ArrayList;
import java.util.List;
import org.lflang.ASTUtils;
import org.lflang.federated.FederateInstance;
import org.lflang.generator.CodeBuilder;
import org.lflang.generator.GeneratorBase;
import org.lflang.generator.ReactorInstance;
import org.lflang.lf.Reaction;
import org.lflang.lf.Reactor;
import org.lflang.lf.ReactorDecl;

public class PythonReactorGenerator {
    /**
     * Wrapper function for the more elaborate generatePythonReactorClass that keeps track
     * of visited reactors to avoid duplicate generation
     * @param instance The reactor instance to be generated
     * @param pythonClasses The class definition is appended to this code builder
     * @param federate The federate instance for the reactor instance
     * @param instantiatedClasses A list of visited instances to avoid generating duplicates
     */
    public static String generatePythonClass(ReactorInstance instance, FederateInstance federate, ReactorInstance main, PythonTypes types) {
        List<String> instantiatedClasses = new ArrayList<String>();
        return generatePythonClass(instance, federate, instantiatedClasses, main, types);
    }

    /**
     * Generate a Python class corresponding to decl
     * @param instance The reactor instance to be generated
     * @param pythonClasses The class definition is appended to this code builder
     * @param federate The federate instance for the reactor instance
     * @param instantiatedClasses A list of visited instances to avoid generating duplicates
     */
    public static String generatePythonClass(ReactorInstance instance, FederateInstance federate, 
                                           List<String> instantiatedClasses, 
                                           ReactorInstance main, PythonTypes types) {
        CodeBuilder pythonClasses = new CodeBuilder();
        ReactorDecl decl = instance.getDefinition().getReactorClass();
        Reactor reactor = ASTUtils.toDefinition(decl);
        String className = instance.getDefinition().getReactorClass().getName();
        if (instance != main && !federate.contains(instance) || 
                instantiatedClasses == null ||
                // Do not generate code for delay reactors in Python
                className.contains(GeneratorBase.GEN_DELAY_CLASS_NAME)) { 
            return "";
        }

        if (federate.contains(instance) && !instantiatedClasses.contains(className)) {
            pythonClasses.pr(generatePythonClassHeader(className));
            // Generate preamble code
            pythonClasses.indent();
            pythonClasses.pr(PythonPreambleGenerator.generatePythonPreamblesForReactor(reactor));
            // Handle runtime initializations
            pythonClasses.pr("def __init__(self, **kwargs):");
            pythonClasses.pr(generatePythonParametersAndStateVariables(decl, types));
            List<Reaction> reactionToGenerate = ASTUtils.allReactions(reactor);
            if (reactor.isFederated()) {
                // Filter out reactions that are automatically generated in C in the top level federated reactor
                reactionToGenerate.removeIf(it -> !federate.contains(it) || federate.networkReactions.contains(it));
            }
            pythonClasses.pr(PythonReactionGenerator.generatePythonReactions(reactor, reactionToGenerate));
            pythonClasses.unindent();
            instantiatedClasses.add(className);
        }

        for (ReactorInstance child : instance.children) {
            pythonClasses.pr(generatePythonClass(child, federate, instantiatedClasses, main, types));
        }
        return pythonClasses.getCode();
    }

    private static String generatePythonClassHeader(String className) {
        return String.join("\n", 
            "# Python class for reactor "+className+"",
            "class _"+className+":"
        );
    }

    /**
     * Generate code that instantiates and initializes parameters and state variables for a reactor 'decl'.
     * 
     * @param decl The reactor declaration
     * @return The generated code as a StringBuilder
     */
     private static String generatePythonParametersAndStateVariables(ReactorDecl decl, PythonTypes types) {
        CodeBuilder code = new CodeBuilder();
        code.indent();
        code.pr(PythonParameterGenerator.generatePythonInstantiations(decl, types));
        code.pr(PythonStateGenerator.generatePythonInstantiations(decl));
        code.unindent();
        code.pr(PythonParameterGenerator.generatePythonGetters(decl));
        return code.toString();
    }
}
