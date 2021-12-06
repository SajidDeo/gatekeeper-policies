package restricthostnames

# Annotation which contains JSON information about exempted Hosts and Paths
annotation := "ingress.statcan.gc.ca/allowed-hosts"
# Allowed hosts scraped from the above annotation.
allowedHosts := json.unmarshal(data.inventory.cluster["v1"].Namespace[input.review.object.metadata.namespace].metadata.annotations[annotation])

identical(obj, review) {
    obj.metadata.namespace == review.object.metadata.namespace
    obj.metadata.name == review.object.metadata.name
}

is_exempt(host) {
    exemption := input.parameters["exemptions"][_]
    glob.match(exemption, [], host)
}

# Host is permitted on namespace
is_allowed(host) {
    allowedHost := allowedHosts[_]
    host == allowedHost.host
}

# Host is permitted on namespace with no path restrictions
is_allowed(host, path) {
    allowedHost := allowedHosts[_]

    host == allowedHost.host
    not allowedHost.path
}

# Host and path is permitted
is_allowed(host, path) {
    allowedHost := allowedHosts[_]

    host == allowedHost.host
    path == allowedHost.path
}

# Host and path is permitted, handling the "/*" prefix for Istio
is_allowed(host, path) {
       allowedHost := allowedHosts[_]

    host == allowedHost.host
    endswith(path, "/*")
    path == concat("", [allowedHost.path, "*"])
}

# Ingress
violation[{"msg": msg}] {
    input.review.kind.kind == "Ingress"
    input.review.kind.group == "networking.k8s.io"

    rule := input.review.object.spec.rules[_]
    host := rule.host
    path := rule.http.paths[_].path

    # Check if the hostname is exempt
    not is_exempt(host)

    # Check if the hostname is allowed
    not is_allowed(host, path)

    msg := sprintf("ingress host <%v> and path <%v> is not allowed for this namespace", [host, path])
}

# Virtual Service
# Common validation for VirtualServices
virtual_service(path) {
    input.review.kind.kind == "VirtualService"
    input.review.kind.group == "networking.istio.io"

    host := input.review.object.spec.hosts[_]

    # Check if the hostname is exempt
    not is_exempt(host)

    # Check if the hostname is allowed
    not is_allowed(host, path)

    msg := sprintf("virtualservice host <%v> and path <%v> is not allowed for this namespace", [host, path])
}

# (prefix)
violation[{"msg": msg}] {
    path := input.review.object.spec.http[_].match[_].uri.prefix

    virtual_service(path)
}

# (exact)
violation[{"msg": msg}] {
    path := input.review.object.spec.http[_].match[_].uri.exact

    virtual_service(path)
}

# (regex)
violation[{"msg": msg}] {
    path := input.review.object.spec.http[_].match[_].uri.regex

    virtual_service(path)
}
