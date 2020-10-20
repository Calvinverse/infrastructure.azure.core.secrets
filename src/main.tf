terraform {
    backend "local" {
    }
}

provider "azurerm" {
  alias  = "production"

  features {}

  subscription_id = var.subscription_production

  version = "~>2.21.0"
}

provider "azurerm" {
    #alias = "target"

    features {}

    subscription_id = var.environment == "production" ? var.subscription_production : var.subscription_test

    version = "~>2.21.0"
}

provider "azuread" {
  version = "=0.11.0"

  subscription_id = var.environment == "production" ? var.subscription_production : var.subscription_test
}


#
# LOCALS
#

locals {
  location_map = {
    australiacentral = "auc",
    australiacentral2 = "auc2",
    australiaeast = "aue",
    australiasoutheast = "ause",
    brazilsouth = "brs",
    canadacentral = "cac",
    canadaeast = "cae",
    centralindia = "inc",
    centralus = "usc",
    eastasia = "ase",
    eastus = "use",
    eastus2 = "use2",
    francecentral = "frc",
    francesouth = "frs",
    germanynorth = "den",
    germanywestcentral = "dewc",
    japaneast = "jpe",
    japanwest = "jpw",
    koreacentral = "krc",
    koreasouth = "kre",
    northcentralus = "usnc",
    northeurope = "eun",
    norwayeast = "noe",
    norwaywest = "now",
    southafricanorth = "zan",
    southafricawest = "zaw",
    southcentralus = "ussc",
    southeastasia = "asse",
    southindia = "ins",
    switzerlandnorth = "chn",
    switzerlandwest = "chw",
    uaecentral = "aec",
    uaenorth = "aen",
    uksouth = "uks",
    ukwest = "ukw",
    westcentralus = "uswc",
    westeurope = "euw",
    westindia = "inw",
    westus = "usw",
    westus2 = "usw2",
  }
}

locals {
  environment_short = substr(var.environment, 0, 1)
  location_short = lookup(local.location_map, var.location, "aue")
}

# Name prefixes
locals {
  name_prefix = "${local.environment_short}-${local.location_short}"
  name_prefix_tf = "${local.name_prefix}-tf-${var.category}-${var.spoke_id}"
}

locals {
  common_tags = {
    category    = "${var.category}"
    datacenter  = "${var.datacenter}-${var.spoke_id}"
    environment = "${var.environment}"
    image_version = "${var.resource_version}"
    location    = "${var.location}"
    source      = "${var.meta_source}"
    version     = "${var.meta_version}"
  }

  extra_tags = {
  }
}

locals {
  admin_username = "thebigkahuna"
}

data "azurerm_client_config" "current" {}

locals {
  spoke_base_name = "t-aue-tf-nwk-spoke-${var.spoke_id}"
  spoke_resource_group = "${local.spoke_base_name}-rg"
  spoke_vnet = "${local.spoke_base_name}-vn"
  service_discovery_base_name = "t-aue-tf-cv-core-sd-${var.spoke_id}"
}

data "azurerm_log_analytics_workspace" "log_analytics_workspace" {
  name = "p-aue-tf-analytics-law-logs"
  provider = azurerm.production
  resource_group_name = "p-aue-tf-analytics-rg"
}

data "azurerm_subnet" "sn" {
  name = "${local.spoke_base_name}-sn"
  virtual_network_name = local.spoke_vnet
  resource_group_name = local.spoke_resource_group
}

data "azuread_group" "secrets_discovery" {
  name = "${local.spoke_base_name}-adg-consul-cloud-join"
}

data "azurerm_resource_group" "secrets_discovery" {
    name = "${local.service_discovery_base_name}-rg"
}


#
# RESOURCE GROUP
#

resource "azurerm_resource_group" "rg" {
    name = "${local.name_prefix_tf}-rg"
    location = var.location

    tags = merge( local.common_tags, local.extra_tags, var.tags )
}

#
# AD GROUP
#

resource "azuread_group" "vault" {
    description = "The collection of users who are allowed to read the Vault unseal secrets from the key vault."
    name = "${local.name_prefix_tf}-adg-vault"
    prevent_duplicate_names = true
}

#
# ROLES
#

resource "azurerm_role_definition" "vault" {
    description = "A custom role that allows Vault nodes to automatically unseal using Azure Key-Vaults."
    name = "${local.name_prefix_tf}-rd-vault"
    scope = azurerm_resource_group.rg.id

    permissions {
        actions = [
          "Microsoft.Compute/virtualMachines/*/read",
          "Microsoft.Compute/virtualMachineScaleSets/*/read",
        ]
        not_actions = []
    }

    assignable_scopes = [
        azurerm_resource_group.rg.id
    ]
}

resource "azurerm_role_assignment" "vault" {
    principal_id  = azuread_group.vault.id
    role_definition_id = azurerm_role_definition.vault.id
    scope = azurerm_resource_group.rg.id
}

#
# KEY VAULT
#

resource "azurerm_key_vault" "keys" {
    enabled_for_deployment  = true
    enabled_for_disk_encryption = true
    location  = var.location
    name  = "${local.name_prefix_tf}-kv"
    purge_protection_enabled = false
    resource_group_name = azurerm_resource_group.rg.name
    sku_name = "standard"
    soft_delete_enabled = false
    tenant_id = data.azurerm_client_config.current.tenant_id

    access_policy [
      {
        tenant_id = data.azurerm_client_config.current.tenant_id
        object_id = data.azurerm_client_config.current.object_id

        certificate_permissions = [
          "backup",
          "create",
          "delete",
          "deleteissuers",
          "get",
          "getissuers",
          "import",
          "list",
          "listissuers",
          "managecontacts",
          "manageissuers",
          "purge",
          "recover",
          "restore",
          "setissuers",
          "update",
        ]

        key_permissions = [
          "backup",
          "create",
          "decrypt",
          "delete",
          "encrypt",
          "get",
          "import",
          "list",
          "purge",
          "recover",
          "restore",
          "sign",
          "unwrapKey",
          "update",
          "verify",
          "wrapKey"
        ]

        secret_permissions = [
          "backup",
          "delete",
          "get",
          "list",
          "purge",
          "recover",
          "restore",
          "set"
        ]

        storage_permissions = [
          "backup",
          "delete",
          "deletesas",
          "get",
          "getsas",
          "list",
          "listsas",
          "purge",
          "recover",
          "regeneratekey",
          "restore",
          "set",
          "setsas",
          "update"
        ]
      },
      {
        tenant_id = data.azurerm_client_config.current.tenant_id
        object_id = azuread_group.vault.id

        certificate_permissions = [
          "create",
          "delete",
          "deleteissuers",
          "get",
          "getissuers",
          "import",
          "list",
          "listissuers",
          "managecontacts",
          "manageissuers",
          "purge",
          "setissuers",
          "update",
        ]

        key_permissions = [
          "create",
          "decrypt",
          "delete",
          "encrypt",
          "get",
          "list",
          "purge",
          "sign",
          "unwrapKey",
          "update",
          "verify",
          "wrapKey"
        ]

        secret_permissions = [
          "delete",
          "get",
          "list",
          "purge",
          "set"
        ]

        storage_permissions = [
          "get",
        ]
      }
    ]

    network_acls {
        default_action = "Deny"
        bypass = "AzureServices"
    }

    tags = merge( local.common_tags, local.extra_tags, var.tags )
}


#
# VAULT
#

locals {
    name_secrets = "secrets"
}

# Locate the existing proxy image
data "azurerm_image" "search_secrets" {
    name = "resource-secrets-${var.resource_version}"
    resource_group_name = "t-aue-artefacts-rg"
}

resource "azurerm_linux_virtual_machine_scale_set" "vmss_secrets" {
    admin_password = var.admin_password
    admin_username = local.admin_username

    automatic_instance_repair {
        enabled = true
    }

    custom_data = base64encode(templatefile(
        "${abspath(path.root)}/cloud_init_client.yaml",
        {
            cluster_size = var.cluster_size,
            consul_cert_bundle = filebase64("${var.consul_cert_path}/${var.domain_consul}-agent-ca.pem"),
            datacenter = "${var.datacenter}-${var.spoke_id}",
            domain = var.domain_consul,
            encrypt = var.encrypt_consul,
            environment_id = local.service_discovery_base_name,
            key_vault_name = "",
            subscription = var.environment == "production" ? var.subscription_production : var.subscription_test,
            vault_unseal_key_name = '',
            vnet_forward_ip = cidrhost(data.azurerm_subnet.sn.address_prefixes[0], 1)
        }))

    disable_password_authentication = false

    identity {
        type = "SystemAssigned"
    }

    instances = var.cluster_size

    location = var.location

    name = "${local.name_prefix_tf}-vmss-${local.name_secrets}"

    network_interface {
        name = "${local.name_prefix_tf}-nic-secrets"
        network_security_group_id = data.azurerm_subnet.sn.network_security_group_id
        primary = true

        ip_configuration {
            name = "${local.name_prefix_tf}-nicconf-secrets"

            primary = true
            subnet_id = data.azurerm_subnet.sn.id
        }
    }

    os_disk {
        caching = "ReadWrite"
        storage_account_type = "Premium_LRS"
    }

    resource_group_name = azurerm_resource_group.rg.name

    sku = "Standard_DS1_v2"

    source_image_id = data.azurerm_image.search_secrets.id

    tags = merge(
        local.common_tags,
        local.extra_tags,
        var.tags,
        {
        } )

    upgrade_mode = "Manual" # Use blue-green approach to upgrades
}

resource "azuread_group_member" "secrets_cluster_discovery" {
    group_object_id = data.azuread_group.secrets_discovery.id
    member_object_id  = azurerm_linux_virtual_machine_scale_set.vmss_secrets.identity.0.principal_id
}

resource "azuread_group_member" "secrets_cluster_discovery" {
    group_object_id = azuread_group.vault.id
    member_object_id  = azurerm_linux_virtual_machine_scale_set.vmss_secrets.identity.0.principal_id
}
