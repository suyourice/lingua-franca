/*
 * Copyright (c) 2021, TU Dresden.
 *
 * Redistribution and use in source and binary forms, with or without modification,
 * are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
 * THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
 * THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

package org.lflang;

import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.lflang.lf.Action;
import org.lflang.lf.Delay;
import org.lflang.lf.Parameter;
import org.lflang.lf.Port;
import org.lflang.lf.StateVar;
import org.lflang.lf.Time;
import org.lflang.lf.TimeUnit;
import org.lflang.lf.Type;
import org.lflang.lf.Value;
import org.lflang.lf.VarRef;

/**
 * Helper class to manipulate the LF AST. This is partly
 * converted from {@link ASTUtils}.
 */
public final class JavaAstUtils {
    /* Match an abbreviated form of a float literal. */
    private static final Pattern ABBREVIATED_FLOAT = Pattern.compile("[+\\-]?\\.\\d+[\\deE+\\-]*");

    private JavaAstUtils() {
        // utility class
    }

    /**
     * Return the type of a declaration with the given
     * (nullable) explicit type, and the given (nullable)
     * initializer. If the explicit type is null, then the
     * type is inferred from the initializer. Only two types
     * can be inferred: "time" and "timeList". Return the
     * "undefined" type if neither can be inferred.
     *
     * @param type     Explicit type declared on the declaration
     * @param initList A list of values used to initialize a parameter or
     *                 state variable.
     * @return The inferred type, or "undefined" if none could be inferred.
     */
    public static InferredType getInferredType(Type type, List<Value> initList) {
        if (type != null) {
            return InferredType.fromAST(type);
        } else if (initList == null) {
            return InferredType.undefined();
        }

        if (initList.size() == 1) {
            // If there is a single element in the list, and it is a proper
            // time value with units, we infer the type "time".
            Value init = initList.get(0);
            if (init.getParameter() != null) {
                return getInferredType(init.getParameter());
            } else if (ASTUtils.isValidTime(init) && !ASTUtils.isZero(init)) {
                return InferredType.time();
            }
        } else if (initList.size() > 1) {
            // If there are multiple elements in the list, and there is at
            // least one proper time value with units, and all other elements
            // are valid times (including zero without units), we infer the
            // type "time list".
            var allValidTime = true;
            var foundNonZero = false;

            for (var init : initList) {
                if (!ASTUtils.isValidTime(init)) {
                    allValidTime = false;
                }
                if (!ASTUtils.isZero(init)) {
                    foundNonZero = true;
                }
            }

            if (allValidTime && foundNonZero) {
                // Conservatively, no bounds are inferred; the returned type
                // is a variable-size list.
                return InferredType.timeList();
            }
        }
        return InferredType.undefined();
    }

    /**
     * Given a parameter, return an inferred type. Only two types can be
     * inferred: "time" and "timeList". Return the "undefined" type if
     * neither can be inferred.
     *
     * @param p A parameter to infer the type of.
     * @return The inferred type, or "undefined" if none could be inferred.
     */
    public static InferredType getInferredType(Parameter p) {
        return getInferredType(p.getType(), p.getInit());
    }

    /**
     * Given a state variable, return an inferred type. Only two types can be
     * inferred: "time" and "timeList". Return the "undefined" type if
     * neither can be inferred.
     *
     * @param s A state variable to infer the type of.
     * @return The inferred type, or "undefined" if none could be inferred.
     */
    public static InferredType getInferredType(StateVar s) {
        return getInferredType(s.getType(), s.getInit());
    }

    /**
     * Construct an inferred type from an "action" AST node based
     * on its declared type. If no type is declared, return the "undefined"
     * type.
     *
     * @param a An action to construct an inferred type object for.
     * @return The inferred type, or "undefined" if none was declared.
     */
    public static InferredType getInferredType(Action a) {
        return getInferredType(a.getType(), null);
    }

    /**
     * Construct an inferred type from a "port" AST node based on its declared
     * type. If no type is declared, return the "undefined" type.
     *
     * @param p A port to construct an inferred type object for.
     * @return The inferred type, or "undefined" if none was declared.
     */
    public static InferredType getInferredType(Port p) {
        return getInferredType(p.getType(), null);
    }

    /**
     * If the given string can be recognized as a floating-point number that has a leading decimal point, 
     * prepend the string with a zero and return it. Otherwise, return the original string.
     * @param literal A string might be recognizable as a floating point number with a leading decimal point.
     * @return an equivalent representation of <code>literal
     * </code>
     */
    public static String addZeroToLeadingDot(String literal) {
        Matcher m = ABBREVIATED_FLOAT.matcher(literal);
        if (m.matches()) return literal.replace(".", "0.");
        return literal;
    }

    ////////////////////////////////
    //// Utility functions for translating AST nodes into text
    // This is a continuation of a large section of ASTUtils.xtend
    // with the same name.

    /**
     * Generate code for referencing a port, action, or timer.
     * @param reference The reference to the variable.
     */
    public static String generateVarRef(VarRef reference) {
        var prefix = "";
        if (reference.getContainer() != null) {
            prefix = reference.getContainer().getName() + ".";
        }
        return prefix + reference.getVariable().getName();
    }

    /**
     * Generate code for referencing a port possibly indexed by
     * a bank index and/or a multiport index. This assumes the target language uses
     * the usual array indexing [n] for both cases. If the provided reference is
     * not a port, then this returns the string "ERROR: not a port."
     * @param reference The reference to the port.
     * @param bankIndex A bank index or null or negative if not in a bank.
     * @param multiportIndex A multiport index or null or negative if not in a multiport.
     */
    public static String generatePortRef(VarRef reference, Integer bankIndex, Integer multiportIndex) {
        // FIXME: Should this be moved to CUtil? It is intended to generalize beyond C, but as of this
        //  writing, only CGenerator and PythonGeneratorExtension use it.
        if (!(reference.getVariable() instanceof Port)) {
            return "ERROR: not a port."; // FIXME: This is not the fail-fast approach, and it seems arbitrary.
        }
        var prefix = "";
        if (reference.getContainer() != null) {
            var bank = "";
            if (reference.getContainer().getWidthSpec() != null && bankIndex != null && bankIndex >= 0) {
                bank = "[" + bankIndex + "]";
            }
            prefix = reference.getContainer().getName() + bank + ".";
        }
        var multiport = "";
        if (((Port) reference.getVariable()).getWidthSpec() != null && multiportIndex != null && multiportIndex >= 0) {
            multiport = "[" + multiportIndex + "]";
        }
        return prefix + reference.getVariable().getName() + multiport;
    }

    /**
     * Given a representation of time that may include units, return
     * a string that the target language can recognize as a value.
     * If units are given, e.g. "msec", then we convert the units to upper
     * case and return an expression of the form "MSEC(value)".
     * @param time A TimeValue that represents a time.
     * @return A string, such as "MSEC(100)" for 100 milliseconds.
     */
    public static String getTargetTime(TimeValue time) {
        // The following apply to other methods in this section.
        // FIXME: This is only used in a few code generators. Does the code reuse achieved justify the
        //  coupling that results from having this common dependency, in comparison to having separate
        //  implementations sequestered in the appropriate packages?
        // FIXME: In Kotlin, this would be done more concisely in the style of AstExtensions.kt.
        if (time != null) {
            if (time.unit != TimeUnit.NONE) {
                return time.unit.name() + '(' + time.time + ')';
            } else {
                return String.valueOf(time.time);
            }
        }
        return "0"; // FIXME: do this or throw exception?
    }

    /**
     * Return the time specified by {@code t}, expressed as
     * code that is valid for some target languages.
     */
    public static String getTargetTime(Time t) {
        return getTargetTime(new TimeValue(t.getInterval(), t.getUnit()));
    }

    /**
     * Return the time specified by {@code d}, expressed as
     * code that is valid for some target languages.
     */
    public static String getTargetTime(Delay d) {
        return d.getParameter() != null ? ASTUtils.toText(d) : getTargetTime(
            ASTUtils.getInitialTimeValue(d.getParameter())  // The time is given as a parameter reference.
        );
    }

    /**
     * Return the time specified by {@code v}, expressed as
     * code that is valid for some target languages.
     */
    public static String getTargetTime(Value v) {
        if (v.getTime() != null) return getTargetTime(v.getTime());
        if (ASTUtils.isZero(v)) return getTargetTime(new TimeValue(0, TimeUnit.NONE));
        return ASTUtils.toText(v);
    }

    /**
     * Get textual representation of a value in the target language.
     *
     * If the value evaluates to 0, it is interpreted as a normal value.
     *
     * @param v A time AST node
     * @return A time string in the target language
     */
    public static String getTargetValue(Value v) {
        // FIXME: This is practically the same as getTargetTime, and it is almost always used for times
        //  (at least in the TypeScript generator). Perhaps it can be eliminated.
        if (v.getTime() != null) return getTargetTime(v.getTime());
        return ASTUtils.toText(v);
    }
}
