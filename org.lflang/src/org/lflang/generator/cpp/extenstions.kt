package org.lflang.generator.cpp

import org.eclipse.emf.ecore.resource.Resource
import org.lflang.ASTUtils
import org.lflang.FileConfig
import org.lflang.lf.Reaction
import org.lflang.lf.Reactor
import org.lflang.toDefinition
import java.nio.file.Path

/*************
 * Copyright (c) 2019-2021, TU Dresden.

 * Redistribution and use in source and binary forms, with or without modification,
 * are permitted provided that the following conditions are met:

 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.

 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.

 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
 * THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
 * THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 ***************/

/* *******************************************************************************************
 * The following definitions are shortcuts to access static members of FileConfig and ASTUtils
 *
 * TODO these should likely be moved to a common place in the future
 */

val Resource.name: String get() = FileConfig.getName(this)

fun Path.toUnixString(): String = FileConfig.toUnixString(this)
fun Path.createDirectories() = FileConfig.createDirectories(this)

val Reactor.isGeneric get() = ASTUtils.isGeneric(this.toDefinition())

/* *******************************************************************************************
 *
 * The following definition provide extension that are likely useful across targets
 *
 * TODO Move these definitions to a common place and check if they are already implemented elsewhere
 */

/** Get the "name" a reaction is represented with in target code.*/
val Reaction.name
    get() :String {
        val r = this.eContainer() as Reactor
        return "r" + r.reactions.lastIndexOf(this)
    }

/** Get a label representing the reaction.
 *
 * If the reactions is annotated with a label, then the label is returned. Otherwise, the reactions name is returned.
 */
val Reaction.label get() :String = ASTUtils.label(this) ?: this.name

/** Get the reactions priority */
val Reaction.priority
    get() :Int {
        val r = this.eContainer() as Reactor
        return r.reactions.lastIndexOf(this) + 1
    }

/* ********************************************************************************************/

/** Prepend each line of the rhs multiline string with the lhs prefix.
 *
 * This is a neat little trick that allows for convenient insertion of multiline strings in string templates
 * while correctly managing the indentation. Consider this multiline string:
 * ```
 * val foo = """
 *    void foo() {
 *        // do something useful
 *    }""".trimIndent()
 * ```
 *
 * It could be inserted into a higher level multiline string like this:
 *
 * ```
 * val bar = """
 *     |class Bar {
 * ${" |    "..foo}
 *     |};""".trimMargin()
 * ```
 *
 * This will produce the expected output:
 * ```
 * class Bar {
 *     void foo() {
 *         // do something useful
 *     }
 * };
 *
 * TODO We likely want to move this to a central place
 * ```
 */
operator fun String.rangeTo(str: String) = str.replaceIndent(this)