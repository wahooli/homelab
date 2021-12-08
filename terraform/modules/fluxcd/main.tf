resource "null_resource" "destroy_remove_finalizers" {
    depends_on  = [kubectl_manifest.sync]
    triggers = {
        namespace   = var.flux_namespace
        kubeconfig  = var.kubeconfig_path
    }

    provisioner "local-exec" {
        command = "echo hello"
    }

    provisioner "local-exec" {
        when       = destroy
        command    = "kubectl --kubeconfig ${self.triggers.kubeconfig} patch customresourcedefinition helmcharts.source.toolkit.fluxcd.io helmreleases.helm.toolkit.fluxcd.io helmrepositories.source.toolkit.fluxcd.io kustomizations.kustomize.toolkit.fluxcd.io -p '{\"metadata\":{\"finalizers\":null}}'"
        on_failure = continue
    }
}

resource "kubernetes_namespace" "flux_namespace" {
    metadata {
        annotations = {
            name = var.flux_namespace
        }
        name = var.flux_namespace
    }

    lifecycle {
        ignore_changes = [
            metadata["annotations"],
            metadata["labels"]
        ]
    }
}

data "flux_install" "main" {
    target_path = var.target_path
}

data "flux_sync" "main" {
    target_path = var.target_path
    url         = "ssh://git@github.com/${var.github_owner}/${var.repository_name}.git"
    branch      = var.branch
}

data "kubectl_file_documents" "install" {
    content = data.flux_install.main.content
}

data "kubectl_file_documents" "sync" {
    content = data.flux_sync.main.content
}

locals {
    install = [for v in data.kubectl_file_documents.install.documents : {
        data : yamldecode(v)
            content : v
        }
    ]
    sync = [for v in data.kubectl_file_documents.sync.documents : {
        data : yamldecode(v)
            content : v
        }
    ]
}

resource "kubectl_manifest" "install" {
    depends_on  = [kubernetes_namespace.flux_namespace]
    for_each    = { for v in local.install : lower(join("/", compact([v.data.apiVersion, v.data.kind, lookup(v.data.metadata, "namespace", ""), v.data.metadata.name]))) => v.content }
    yaml_body   = each.value
}

resource "kubectl_manifest" "sync" {
    depends_on  = [kubectl_manifest.install, kubernetes_namespace.flux_namespace]
    for_each    = { for v in local.sync : lower(join("/", compact([v.data.apiVersion, v.data.kind, lookup(v.data.metadata, "namespace", ""), v.data.metadata.name]))) => v.content }
    yaml_body   = each.value
}

locals {
    known_hosts = "github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg="
}

resource "tls_private_key" "github_deploy_key" {
    algorithm   = "RSA"
    rsa_bits    = 4096
}

resource "kubernetes_secret" "main" {
    depends_on = [kubectl_manifest.install]

    metadata {
        name            = data.flux_sync.main.secret
        namespace       = data.flux_sync.main.namespace
    }

    data = {
        known_hosts     = local.known_hosts
        identity        = tls_private_key.github_deploy_key.private_key_pem
        "identity.pub"  = tls_private_key.github_deploy_key.public_key_openssh
    }

    lifecycle {
        ignore_changes = [
            metadata["annotations"],
            metadata["labels"]
        ]
    }
}

# Github
provider "github" {
    token           = var.github_token
    owner           = var.github_owner
}

# To make sure the repository exists and the correct permissions are set.
data "github_repository" "main" {
    full_name = "${var.github_owner}/${var.repository_name}"
}

resource "github_repository_file" "install" {
    repository          = data.github_repository.main.name
    file                = data.flux_install.main.path
    content             = data.flux_install.main.content
    branch              = var.branch
    overwrite_on_create = true
}

resource "github_repository_file" "sync" {
    repository          = var.repository_name
    file                = data.flux_sync.main.path
    content             = data.flux_sync.main.content
    branch              = var.branch
    overwrite_on_create = true
}

resource "github_repository_file" "kustomize" {
    repository          = var.repository_name
    file                = data.flux_sync.main.kustomize_path
    content             = data.flux_sync.main.kustomize_content
    branch              = var.branch
    overwrite_on_create = true
}

# For flux to fetch source
resource "github_repository_deploy_key" "flux" {
    title               = var.github_deploy_key_title
    repository          = data.github_repository.main.name
    key                 = tls_private_key.github_deploy_key.public_key_openssh
    read_only           = true
}