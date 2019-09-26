/*
 * generated by Xtext 2.17.0
 */
package org.icyphy.scoping

import com.google.inject.Inject
import java.util.ArrayList
import org.eclipse.emf.ecore.EObject
import org.eclipse.emf.ecore.EReference
import org.eclipse.xtext.naming.SimpleNameProvider
import org.eclipse.xtext.scoping.IScope
import org.eclipse.xtext.scoping.Scopes
import org.icyphy.linguaFranca.Reactor
import org.icyphy.linguaFranca.TriggerRef
import org.icyphy.linguaFranca.SourceRef
import org.icyphy.linguaFranca.EffectRef

/**
 * This class enforces custom rules. In particular, it resolves references to 
 * ports, actions, and timers. Ports can be referenced across at most one level
 * of hierarchy. Only local actions and timers can be referenced.
 * 
 * See https://www.eclipse.org/Xtext/documentation/303_runtime_concepts.html#scoping
 * on how and when to use it.
 */
class LinguaFrancaScopeProvider extends AbstractLinguaFrancaScopeProvider {

	@Inject SimpleNameProvider nameProvider

	override getScope(EObject context, EReference reference) {
		switch (context) {
			SourceRef: return getScopeForSourceRef(context, reference)
			TriggerRef: return getScopeForTriggerRef(context, reference)
			EffectRef: return getScopeForEffectRef(context, reference)
		}
		return super.getScope(context, reference);
	}
		
	protected def getScopeForEffectRef(EffectRef effect, EReference reference) {
		if (reference.name.equals("variable")) { // Resolve hierarchical port reference
			val reactor = effect.eContainer.eContainer as Reactor;
			if (effect.instance !== null) {
				val instanceName = nameProvider.getFullyQualifiedName(effect.instance).toString;
				val instances = reactor.instances;
				for (instance : instances) {
					if (instance.name.equals(instanceName)) {
						return Scopes.scopeFor(instance.reactorClass.inputs);
					}
				}
			} else { // Resolve local port reference or action
				val candidates = new ArrayList<EObject>();
				candidates.addAll(reactor.outputs)
				candidates.addAll(reactor.actions)
				return Scopes.scopeFor(candidates)
			}
		} else { // Resolve instance
			return super.getScope(effect, reference);
		}
	}

	protected def getScopeForTriggerRef(TriggerRef trigger, EReference reference) {
		if (reference.name.equals("variable")) { // Resolve hierarchical port reference
			val reactor = trigger.eContainer.eContainer as Reactor;
			if (trigger.instance !== null) {
				val instanceName = nameProvider.getFullyQualifiedName(trigger.instance).toString;
				val instances = reactor.instances;
				for (instance : instances) {
					if (instance.name.equals(instanceName)) {
						return Scopes.scopeFor(instance.reactorClass.outputs);
					}
				}
			} else { // Resolve local port reference, action, or timer
				val candidates = new ArrayList<EObject>();
				candidates.addAll(reactor.inputs)
				candidates.addAll(reactor.actions)
				candidates.addAll(reactor.timers)
				return Scopes.scopeFor(candidates)
			}
		} else { // Resolve instance
			return super.getScope(trigger, reference);
		}
	}

	protected def IScope getScopeForSourceRef(SourceRef port, EReference reference) {
		if (reference.name.equals("port")) { // Resolve hierarchical port reference
			val reactor = port.eContainer.eContainer as Reactor;
			if (port.instance !== null) {
				val instanceName = nameProvider.getFullyQualifiedName(port.instance).toString;
				val instances = reactor.instances;
				for (instance : instances) {
					if (instance.name.equals(instanceName)) {
						return Scopes.scopeFor(instance.reactorClass.outputs);
					}
				}
			} else { // Resolve local port reference
				return Scopes.scopeFor(reactor.inputs)
			}
		} else { // Resolve instance
			return super.getScope(port, reference);
		}
	}
}
