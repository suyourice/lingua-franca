/* Custom global scope provider for Lingua Franca. */

package org.icyphy.scoping

import org.eclipse.xtext.scoping.impl.ImportUriGlobalScopeProvider

import com.google.common.base.Splitter
import com.google.inject.Inject
import com.google.inject.Provider
import java.util.LinkedHashSet
import org.eclipse.emf.common.util.URI
import org.eclipse.emf.ecore.resource.Resource
import org.eclipse.xtext.EcoreUtil2
import org.eclipse.xtext.resource.IResourceDescription
import org.eclipse.xtext.util.IResourceScopeCache
import org.icyphy.linguaFranca.LinguaFrancaPackage
import org.icyphy.LinguaFrancaResourceDescriptionStrategy

/** Global scope provider designed to limit global scope to the current
 * project directory.
 */
class LinguaFrancaGlobalScopeProvider extends ImportUriGlobalScopeProvider {
    // Note: Adapted from Xtext manual.
    // See https://www.eclipse.org/Xtext/documentation/2.6.0/Xtext%20Documentation.pdf Chapter 8.7
    static final Splitter SPLITTER = Splitter.on(LinguaFrancaResourceDescriptionStrategy.DELIMITER);
    
//    @Inject
//    IContainer.Manager containerManager;

    @Inject
    IResourceDescription.Manager descriptionManager;

//    /* Access to resources are constrained in Xtext by the container manager, which is language specific.
//     * Therefore, the first step in acquiring the resource is to get its corresponding container. 
//     * This function returns a list of containers that contain a specific resource.
//     * @param resource
//     * @return A list of visible containers that have access to the resource. 
//     */
//    override List<IContainer> getVisibleContainers(Resource resource) {
//        // Get the contents of the resource in the form of an ISelectable that holds the imported names
//        // from a given resource.
//        val description = descriptionManager.getResourceDescription(resource);
//        // A flat index that contains all resource descriptions
//        val resourceDescriptions = getResourceDescriptions(resource);
//
//        // Cache management for faster retrieval of visible containers
//        val cacheKey = getCacheKey("VisibleContainers",
//            resource.getResourceSet());
//        val cache = new OnChangeEvictingCache().getOrCreate(resource);
//        var result = cache.get(cacheKey as Object);
//        if (result === null) {
//            // If a resource's container is not in cache, actually use the container manager.
//            result = containerManager.getVisibleContainers(description,
//                resourceDescriptions);
//            if (resourceDescriptions instanceof IResourceDescription.Event.Source) {
//                val eventSource = resourceDescriptions as Source;
//                var delegatingEventSource = new DelegatingEventSource(
//                    eventSource);
//                delegatingEventSource.addListeners(
//                    Lists.newArrayList(
//                        Iterables.filter(result,
//                            IResourceDescription.Event.Listener)));
//                delegatingEventSource.initialize();
//                cache.addCacheListener(delegatingEventSource);
//            }
//            cache.set(cacheKey, result);
//        }
//        return result;
//    }
    
    @Inject
    IResourceScopeCache cache;

    override protected getImportedUris(Resource resource) {
        return cache.get(LinguaFrancaGlobalScopeProvider.getSimpleName(), resource, new Provider<LinkedHashSet<URI>>() {
            override get() {
                val uniqueImportURIs = collectImportUris(resource, new LinkedHashSet<URI>(5))

                val uriIter = uniqueImportURIs.iterator()
                while(uriIter.hasNext()) {
                    if (!EcoreUtil2.isValidUri(resource, uriIter.next()))
                        uriIter.remove()
                }
                return uniqueImportURIs
            }
            
            /**
             * 
             */
            def LinkedHashSet<URI> collectImportUris(Resource resource, LinkedHashSet<URI> uniqueImportURIs) {
                for (imported : getImportedResources(resource, uniqueImportURIs)) {
                    collectImportUris(imported, uniqueImportURIs)
                }
                return uniqueImportURIs
            }
        });
    }
    
    def getImportedResources(Resource resource) {
        return getImportedResources(resource, newLinkedHashSet)
    }
    
    /**
     * Resolve a resource identifier.
     * 
     * @param uriStr resource identifier to resolve.
     * @param resource resource to (initially) resolve it relative to.
     */
    protected def URI resolve(String uriStr, Resource resource) {
        var uriObj = URI.createURI(uriStr)
        val uriExtension = uriObj?.fileExtension
        if (uriExtension !== null && uriExtension.equalsIgnoreCase('lf')) {
            uriObj = uriObj.resolve(resource.URI)
            // FIXME: If this doesn't work, try other things:
            // (1) Look for a .project file up the file structure and try to resolve relative to the directory in which it is found.
            // (2) Look for package description files try to resolve relative to the paths it includes.
            return uriObj
        }
    }
    
    protected def getImportedResources(Resource resource, LinkedHashSet<URI> uniqueImportURIs) {
        val resourceDescription = descriptionManager.getResourceDescription(resource)
        val models = resourceDescription.getExportedObjectsByType(LinguaFrancaPackage.Literals.MODEL)
        val resources = new LinkedHashSet<Resource>()
        models.forEach[
            val userData = getUserData(LinguaFrancaResourceDescriptionStrategy.INCLUDES)
            if (userData !== null) {
                SPLITTER.split(userData).forEach[uri |
                    var includedUri = uri.resolve(resource)
                    if (includedUri !== null) {
                        if(uniqueImportURIs.add(includedUri)) {
                            resources.add(resource.getResourceSet().getResource(includedUri, true))
                        }
                    }
                ]
            }
        ]
        
        return resources
    }
}
