#!/usr/bin/env bash
# =============================================================================
# Script de déploiement Azure - Projet TaskManager avec Key Vault
# Date: 12/11/2025
# Description: Déploiement automatisé de l'infrastructure Azure avec sécurité renforcée
# =============================================================================

set -e  # Arrêt du script en cas d'erreur
set -o pipefail

# =============================================================================
# VARIABLES DE CONFIGURATION
# =============================================================================

# Génération d’un suffixe aléatoire pour garantir l’unicité
randomSuffix=$((RANDOM % 9000 + 1000))

# Paramètres globaux
resourceGroup="RG-TaskManager"
location="polandcentral"

# Réseau
vnetName="VNet-TaskLab"
vnetPrefix="10.0.0.0/16"
subnetName="Subnet-App"
subnetPrefix="10.0.1.0/24"

# MySQL
mysqlServerName="taskmysql${randomSuffix}"
mysqlAdminUser="adminstudent"
mysqlAdminPassword="admin"
mysqlDatabase="taskdb"

# App Service
appServicePlan="asp-task-linux"
webAppName="wa-taskmanager${randomSuffix}"

# VM
vmName="vm-supervision"
vmAdminUser="student"

# Storage Account
storageAccountName="sttaskmanager${randomSuffix}"

# Key Vault
keyVaultName="kv-taskmanager${randomSuffix}"

# =============================================================================
# FONCTION: Afficher un message de progression
# =============================================================================
function progress() {
    echo -e "\n\e[36m========================================\e[0m"
    echo -e "\e[33m$1\e[0m"
    echo -e "\e[36m========================================\e[0m\n"
}

# =============================================================================
# DEBUT DU DEPLOIEMENT
# =============================================================================

progress "🚀 DÉMARRAGE DU DÉPLOIEMENT AZURE TASKMANAGER"

# -------------------------------------------------------------------------
# 1. Groupe de ressources
# -------------------------------------------------------------------------
progress "Étape 1/9: Création du groupe de ressources"
az group create --name "$resourceGroup" --location "$location"

# -------------------------------------------------------------------------
# 2. Réseau virtuel
# -------------------------------------------------------------------------
progress "Étape 2/9: Création du réseau virtuel et sous-réseau"
az network vnet create \
  --name "$vnetName" \
  --resource-group "$resourceGroup" \
  --address-prefix "$vnetPrefix" \
  --subnet-name "$subnetName" \
  --subnet-prefix "$subnetPrefix"

# -------------------------------------------------------------------------
# 3. Serveur MySQL Flexible
# -------------------------------------------------------------------------
progress "Étape 3/9: Création du serveur MySQL Flexible"
az mysql flexible-server create \
  --name "$mysqlServerName" \
  --resource-group "$resourceGroup" \
  --location "$location" \
  --admin-user "$mysqlAdminUser" \
  --admin-password "$mysqlAdminPassword" \
  --sku-name Standard_B1ms \
  --tier Burstable \
  --storage-size 20 \
  --version 8.0.21 \
  --public-access 0.0.0.0 \
  --database-name "$mysqlDatabase" \
  --yes \
  --output none

# -------------------------------------------------------------------------
# 4. Key Vault
# -------------------------------------------------------------------------
progress "Étape 4/9: Création du Key Vault"
az keyvault create \
  --name "$keyVaultName" \
  --resource-group "$resourceGroup" \
  --location "$location" \
  --enable-rbac-authorization false

mysqlFqdn=$(az mysql flexible-server show \
  --resource-group "$resourceGroup" \
  --name "$mysqlServerName" \
  --query "fullyQualifiedDomainName" -o tsv)

connectionString="Server=$mysqlFqdn;Database=$mysqlDatabase;Uid=$mysqlAdminUser;Pwd=$mysqlAdminPassword;SslMode=Required;"

progress "Stockage des secrets dans Key Vault..."
az keyvault secret set --vault-name "$keyVaultName" --name "mysql-server" --value "$mysqlFqdn"
az keyvault secret set --vault-name "$keyVaultName" --name "mysql-username" --value "$mysqlAdminUser"
az keyvault secret set --vault-name "$keyVaultName" --name "mysql-password" --value "$mysqlAdminPassword"
az keyvault secret set --vault-name "$keyVaultName" --name "mysql-database" --value "$mysqlDatabase"
az keyvault secret set --vault-name "$keyVaultName" --name "mysql-connection-string" --value "$connectionString"

# -------------------------------------------------------------------------
# 5. App Service Plan
# -------------------------------------------------------------------------
progress "Étape 5/9: Création du Plan App Service"
az appservice plan create \
  --name "$appServicePlan" \
  --resource-group "$resourceGroup" \
  --location "$location" \
  --sku B1 \
  --is-linux

# -------------------------------------------------------------------------
# 6. Web App
# -------------------------------------------------------------------------
progress "Étape 6/9: Création de la Web App"
az webapp create \
  --name "$webAppName" \
  --resource-group "$resourceGroup" \
  --plan "$appServicePlan" \
  --runtime "NODE:18-lts"

# -------------------------------------------------------------------------
# 7. Managed Identity + Permissions Key Vault
# -------------------------------------------------------------------------
progress "Étape 7/9: Activation Managed Identity et permissions Key Vault"
principalId=$(az webapp identity assign -n "$webAppName" -g "$resourceGroup" --query principalId -o tsv)
az keyvault set-policy --name "$keyVaultName" --object-id "$principalId" --secret-permissions get list

# Configuration App Settings avec Key Vault references
progress "Configuration des App Settings avec références Key Vault"
keyVaultUri="https://${keyVaultName}.vault.azure.net"

az webapp config appsettings set \
  --name "$webAppName" \
  --resource-group "$resourceGroup" \
  --settings \
  "MYSQL_SERVER=@Microsoft.KeyVault(SecretUri=${keyVaultUri}/secrets/mysql-server/)" \
  "MYSQL_USERNAME=@Microsoft.KeyVault(SecretUri=${keyVaultUri}/secrets/mysql-username/)" \
  "MYSQL_PASSWORD=@Microsoft.KeyVault(SecretUri=${keyVaultUri}/secrets/mysql-password/)" \
  "MYSQL_DATABASE=@Microsoft.KeyVault(SecretUri=${keyVaultUri}/secrets/mysql-database/)" \
  "MYSQL_CONNECTION_STRING=@Microsoft.KeyVault(SecretUri=${keyVaultUri}/secrets/mysql-connection-string/)"

# -------------------------------------------------------------------------
# 8. Storage Account
# -------------------------------------------------------------------------
progress "Étape 8/9: Création du Storage Account"
az storage account create \
  --name "$storageAccountName" \
  --resource-group "$resourceGroup" \
  --location "$location" \
  --sku Standard_LRS \
  --kind StorageV2

az storage container create \
  --name logs \
  --account-name "$storageAccountName" \
  --auth-mode login

# -------------------------------------------------------------------------
# 9. VM de supervision
# -------------------------------------------------------------------------
progress "Étape 9/9: Création de la VM de supervision"
sshKeyPath="$HOME/.ssh/id_rsa.pub"

if [ ! -f "$sshKeyPath" ]; then
  echo "Clé SSH non trouvée. Utilisation d'un mot de passe par défaut."
  az vm create \
    --resource-group "$resourceGroup" \
    --name "$vmName" \
    --image Ubuntu2204 \
    --admin-username "$vmAdminUser" \
    --admin-password "admin" \
    --size Standard_B1s \
    --vnet-name "$vnetName" \
    --subnet "$subnetName" \
    --public-ip-sku Standard
else
  az vm create \
    --resource-group "$resourceGroup" \
    --name "$vmName" \
    --image Ubuntu2204 \
    --admin-username "$vmAdminUser" \
    --ssh-key-values "$sshKeyPath" \
    --size Standard_B1s \
    --vnet-name "$vnetName" \
    --subnet "$subnetName" \
    --public-ip-sku Standard
fi

# ------------------------------------------------------------------------
# ETAPE 10: Deploiement de l'application dans App Service
# ------------------------------------------------------------------------
progress "Etape 10/10: Deploiement de l'application dans App Service"

# Le chemin vers app.zip
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

APP_ZIP_PATH="$(realpath "$SCRIPT_DIR/../../app.zip")"

# Check the file exists
if [[ ! -f "$APP_ZIP_PATH" ]]; then
    echo "❌ app.zip not found at $APP_ZIP_PATH"
    exit 1
fi

echo "Déploiement de l'application depuis $APP_ZIP_PATH ..."

az webapp deployment source config-zip -g $resourceGroup -n $webAppName --src $APP_ZIP_PATH


echo "✅ Application déployée avec succès sur App Service !"
echo "URL de l'application : https://$webAppName.azurewebsites.net"


# -------------------------------------------------------------------------
# Azure Monitor
# -------------------------------------------------------------------------
progress "Configuration Azure Monitor"
if az monitor app-insights component create \
  --app "$webAppName" \
  --location "$location" \
  --resource-group "$resourceGroup" \
  --application-type web >/dev/null; then
  instrumentationKey=$(az monitor app-insights component show \
    --app "$webAppName" \
    --resource-group "$resourceGroup" \
    --query "instrumentationKey" -o tsv)
  az webapp config appsettings set \
    --name "$webAppName" \
    --resource-group "$resourceGroup" \
    --settings "APPINSIGHTS_INSTRUMENTATIONKEY=$instrumentationKey"
fi

# -------------------------------------------------------------------------
# RÉSUMÉ
# -------------------------------------------------------------------------
progress "✅ DÉPLOIEMENT TERMINÉ AVEC SUCCÈS"

echo "URL de l'application: https://${webAppName}.azurewebsites.net"
echo "Key Vault: ${keyVaultName}"
echo "Base MySQL: ${mysqlServerName} (${mysqlDatabase})"
echo "VM de supervision: ${vmName}"
echo "Pour supprimer: az group delete -n ${resourceGroup} --yes --no-wait"
