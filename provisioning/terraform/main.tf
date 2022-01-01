terraform {
    required_providers {
        proxmox = {
            source  = "telmate/proxmox"
            version = ">= 2.9.0"
        }
    }
    required_version = ">= 1.0.0"
    experiments = [module_variable_optional_attrs]
}

provider "proxmox" {
    # Configuration options
    pm_api_url          = var.proxmox_api_url
    pm_api_token_id     = var.proxmox_api_token_id
    pm_api_token_secret = var.proxmox_api_token_secret
    pm_tls_insecure     = var.proxmox_ignore_tls
    pm_parallel         = 4 # having 6 as parallel, gives errors for already running vm for some reason
    pm_log_enable       = false
    pm_debug            = false
    pm_log_levels = {
        _default = "debug"
        _capturelog = ""
    }
}


# # github provider for fluxcd
# provider "github" {
#     token           = var.github_token
#     owner           = var.github_owner
# }

module "k3s_cluster" {
    source          = "./deployments/k3s_cluster"
    flux_path       = "cluster"
    repository_name = "homelab"
    github_owner    = var.github_owner
    github_token    = var.github_token
    key_fp          = var.key_fp
}

# module "fluxcd" {
#     source = "./modules/fluxcd"
#     # depends_on = [
#     #     module.k3s_cluster.kubeconfig
#     # ]
#     github_token = var.github_token
#     github_owner = var.github_owner
#     target_path = "${path.module}/../clusters/k3s-at-home"
# }