provider "azurerm" {
  version = "~>2.0"
  features {}
}

data "azurerm_key_vault_secret" "domain_password" {
name = "domainpassword"
key_vault_id = "/subscriptions/9d191167-e723-4876-a390-f671aabeba73/resourceGroups/WVD-Fin-APP01-HP02-TF/providers/Microsoft.KeyVault/vaults/akvwvd101"
}

data "azurerm_key_vault_secret" "tenant_app_password" {
name = "tenantapppassword"
key_vault_id = "/subscriptions/9d191167-e723-4876-a390-f671aabeba73/resourceGroups/WVD-Fin-APP01-HP02-TF/providers/Microsoft.KeyVault/vaults/akvwvd101"
}

resource "random_string" "wvd-local-password" {
  count            = "${var.rdsh_count}"
  length           = 16
  special          = true
  min_special      = 2
  override_special = "*!@#?"
}

resource "azurerm_network_interface" "rdsh" {
  count                     = "${var.rdsh_count}"
  name                      = "${var.vm_prefix}-${count.index +1}-nic"
  location                  = "${var.region}"
  resource_group_name       = "${var.resource_group_name}"

  ip_configuration {
    name                          = "${var.vm_prefix}-${count.index +1}-nic-01"
    subnet_id                     = "${var.subnet_id}"
    private_ip_address_allocation = "dynamic"
  }

  tags = {
    BUC             = "${var.tagBUC}"
    SupportGroup    = "${var.tagSupportGroup}"
    AppGroupEmail   = "${var.tagAppGroupEmail}"
    EnvironmentType = "${var.tagEnvironmentType}"
    CustomerCRMID   = "${var.tagCustomerCRMID}"
  }
}

resource "azurerm_virtual_machine" "main" {
  count                 = "${var.rdsh_count}"
  name                  = "${var.vm_prefix}-${count.index + 1}"
  location              = "${var.region}"
  resource_group_name   = "${var.resource_group_name}"
  network_interface_ids = ["${azurerm_network_interface.rdsh.*.id[count.index]}"]
  vm_size               = "${var.vm_size}"
  availability_set_id   = "${azurerm_availability_set.main.id}"

  delete_os_disk_on_termination    = true
  delete_data_disks_on_termination = true

  storage_image_reference {
    id        = "${var.vm_image_id != "" ? var.vm_image_id : ""}"
    publisher = "${var.vm_image_id == "" ? var.vm_publisher : ""}"
    offer     = "${var.vm_image_id == "" ? var.vm_offer : ""}"
    sku       = "${var.vm_image_id == "" ? var.vm_sku : ""}"
    version   = "${var.vm_image_id == "" ? var.vm_version : ""}"
  }

  storage_os_disk {
    name              = "${lower(var.vm_prefix)}-${count.index +1}"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Premium_LRS"
    disk_size_gb      = "${var.vm_storage_os_disk_size}"
  }

  os_profile {
    computer_name  = "${var.vm_prefix}-${count.index +1}"
    admin_username = "${var.local_admin_username}"
    admin_password = "${random_string.wvd-local-password.*.result[count.index]}"
  }

  os_profile_windows_config {
    provision_vm_agent        = true
    enable_automatic_upgrades = true
    timezone                  = "${var.vm_timezone}"
  }

  tags = {
    BUC               = "${var.tagBUC}"
    SupportGroup      = "${var.tagSupportGroup}"
    AppGroupEmail     = "${var.tagAppGroupEmail}"
    EnvironmentType   = "${var.tagEnvironmentType}"
    CustomerCRMID     = "${var.tagCustomerCRMID}"
    ExpirationDate    = "${var.tagExpirationDate}"
    Tier              = "${var.tagTier}"
    SolutionCentralID = "${var.tagSolutionCentralID}"
    SLA               = "${var.tagSLA}"
    Description       = "${var.tagDescription}"
  }
}

resource "azurerm_managed_disk" "managed_disk" {
  count                = "${var.managed_disk_sizes[0] != "" ? (var.rdsh_count * length(var.managed_disk_sizes)) : 0 }"
  name                 = "${var.vm_prefix}-${(count.index / length(var.managed_disk_sizes)) + 1}-disk-${(count.index % length(var.managed_disk_sizes)) + 1}"
  location             = "${var.region}"
  resource_group_name  = "${var.resource_group_name}"
  storage_account_type = "${var.managed_disk_type}"
  create_option        = "Empty"
  disk_size_gb         = "${var.managed_disk_sizes[count.index % length(var.managed_disk_sizes)]}"

  tags = {
    BUC             = "${var.tagBUC}"
    SupportGroup    = "${var.tagSupportGroup}"
    AppGroupEmail   = "${var.tagAppGroupEmail}"
    EnvironmentType = "${var.tagEnvironmentType}"
    CustomerCRMID   = "${var.tagCustomerCRMID}"
    NPI             = "${var.tagNPI}"
    ExpirationDate  = "${var.tagExpirationDate}"
    SLA             = "${var.tagSLA}"
  }
}

resource "azurerm_virtual_machine_data_disk_attachment" "managed_disk" {
  count              = "${var.managed_disk_sizes[0] != "" ? (var.rdsh_count * length(var.managed_disk_sizes)) : 0 }"
  managed_disk_id    = "${azurerm_managed_disk.managed_disk.*.id[count.index]}"
  virtual_machine_id = "${azurerm_virtual_machine.main.*.id[count.index / length(var.managed_disk_sizes)]}"
  lun                = "10"
  caching            = "ReadWrite"
}



resource "azurerm_virtual_machine_extension" "domainJoin" {
  count                      = "${var.domain_joined ? var.rdsh_count : 0}"
  name                       = "${var.vm_prefix}-${count.index +1}-domainJoin"
  virtual_machine_id         = "${azurerm_virtual_machine.main.*.id[count.index]}"
  publisher                  = "Microsoft.Compute"
  type                       = "JsonADDomainExtension"
  type_handler_version       = "1.3"
  auto_upgrade_minor_version = true
  
  lifecycle {
    ignore_changes = [
      "settings",
      "protected_settings",
    ]
  }

  settings = <<SETTINGS
    {
        "Name": "${var.domain_name}",
        "User": "${var.domain_user_upn}@${var.domain_name}",
        "Restart": "true",
        "Options": "3"
    }
SETTINGS


  protected_settings = <<PROTECTED_SETTINGS
  {
         "Password": "${data.azurerm_key_vault_secret.domain_password.value}"
  }
PROTECTED_SETTINGS


  tags = {
    BUC             = "${var.tagBUC}"
    SupportGroup    = "${var.tagSupportGroup}"
    AppGroupEmail   = "${var.tagAppGroupEmail}"
    EnvironmentType = "${var.tagEnvironmentType}"
    CustomerCRMID   = "${var.tagCustomerCRMID}"
  }
}

resource "azurerm_virtual_machine_extension" "additional_session_host_dscextension" {
  count                      = "${var.rdsh_count}"
  name                       = "${var.vm_prefix}${count.index +1}-wvd_dsc"
  virtual_machine_id         = "${azurerm_virtual_machine.main.*.id[count.index]}"
  publisher                  = "Microsoft.Powershell"
  type                       = "DSC"
  type_handler_version       = "2.73"
  auto_upgrade_minor_version = true
  depends_on                 = ["azurerm_virtual_machine_extension.domainJoin"]

  settings = <<SETTINGS
{
    "modulesURL": "${var.base_url}/DSC/Configuration.zip",
    "configurationFunction": "Configuration.ps1\\RegisterSessionHost",
     "properties": {
        "TenantAdminCredentials":{
            "userName":"${var.tenant_app_id}",
            "password":"PrivateSettingsRef:tenantAdminPassword"
        },
        "RDBrokerURL":"${var.RDBrokerURL}",
        "DefinedTenantGroupName":"${var.existing_tenant_group_name}",
        "TenantName":"${var.tenant_name}",
        "HostPoolName":"${var.host_pool_name}",
        "Hours":"${var.registration_expiration_hours}",
        "isServicePrincipal":"${var.is_service_principal}",
        "AadTenantId":"${var.aad_tenant_id}"
  }
}

SETTINGS

  protected_settings = <<PROTECTED_SETTINGS
{
  "items":{
    "tenantAdminPassword":"${data.azurerm_key_vault_secret.tenant_app_password.value}"
  }
}
PROTECTED_SETTINGS

  tags = {
    BUC             = "${var.tagBUC}"
    SupportGroup    = "${var.tagSupportGroup}"
    AppGroupEmail   = "${var.tagAppGroupEmail}"
    EnvironmentType = "${var.tagEnvironmentType}"
    CustomerCRMID   = "${var.tagCustomerCRMID}"
  }
}
