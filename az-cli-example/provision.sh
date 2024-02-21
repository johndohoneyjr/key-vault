#!/usr/bin/env bash

# Environment Variables
export SUBSCRIPTION_ID=""
export RESOURCE_GROUP="optimal-blue-rg"
export LOCATION="eastus"
export SERVICE_PRINCIPAL_NAME="serviceprincipal"
export GITHUB_REPO="https://github.com/johndohoneyjr/key-vault"

# for alias in WSL - alias expansion needed in scripts, not interactive
shopt -s expand_aliases


# Enter the Customer Name and store in a variable
echo "Enter the Customer Name: "
read customerName
# concatenate the customer name to the resource group name
export RESOURCE_GROUP=$customerName-$RESOURCE_GROUP
echo $RESOURCE_GROUP
# export the customer name as an environment variable
export CUSTOMER_NAME=$customerName

export CUSTOMER=$(echo "$CUSTOMER_NAME" | tr '[:lower:]' '[:upper:]')

# check for existence of environment variable WSL_DISTRO_NAME
# Make sure github cli is installed -- for adding the secret to GH Actions
# https://github.com/cli/cli
#
if [[ -z "${WSL_DISTRO_NAME}" ]]; then
  echo "Not running in WSL, skipping WSL specific commands"
else 
  alias gh="gh.exe"
fi


command -v gh >/dev/null 2>&1 || { echo >&2 "I require gh cli for this script, but it's not installed, download gh at: https://github.com/cli/cli .  Aborting."; exit 1; }

# Make sure jq is installed -- very handy command line tool
# https://stedolan.github.io/jq/download/
#
command -v jq >/dev/null 2>&1 || { echo >&2 "I require jq for this script, but it's not installed, download jq at: https://stedolan.github.io/jq/download/.  Aborting."; exit 1; }

if [[ -z "${SUBSCRIPTION_ID}" ]]; then
  clear
  echo "Please set SUBSCRIPTION_ID to the account you wish to use"
  exit 1
else 
  echo "Using Subscription ID=$SUBSCRIPTION_ID for the following command set"
fi

if [[ -z "${RESOURCE_GROUP}" ]]; then
  clear
  echo "Please set RESOURCE_GROUP for the account you wish to use"
  exit 1
else 
  echo "Using Resource Group =$RESOURCE_GROUP for the following commands"
fi

if [[ -z "${LOCATION}" ]]; then
  clear
  echo "Please set LOCATION for the location you wish to use for set up, locations availaable..."
  az account list-locations | jq .[].metadata.pairedRegion[].name
  exit 1
else 
  echo "Using Resource Group =$LOCATION for the following commands"
fi

if [[ -z "${SERVICE_PRINCIPAL_NAME}" ]]; then
  clear
  echo "Please set SERVICE_PRINCIPAL_NAME for the account you wish to use"
  exit 1
else 
  echo "Using Service Principal Name = $SERVICE_PRINCIPAL_NAME for the following commands"
fi

if [[ -z "${GITHUB_REPO}" ]]; then
  clear
  echo "Please set the GITHUB_REPO you wish to use to set the Service Principal as a secret"
  exit 1
else 
  echo "Using Github Repo = $GITHUB_REPO for GH Actions secrets"
fi

# Login to Owner account
echo ""
echo "Logging you into your account ..."
az login  ## for CodeSpaces --use-device-code
az account set --subscription $SUBSCRIPTION_ID

# Create the Resource Group
echo "Creating resource group - $RESOURCE_GROUP"
az group create --name $RESOURCE_GROUP --location $LOCATION

echo "Creating Resource Group Scoped Service Principal..."
export SERVICE_PRINCIPAL_NAME=$CUSTOMER-$SERVICE_PRINCIPAL_NAME
az ad sp create-for-rbac --name $SERVICE_PRINCIPAL_NAME --role Contributor --scopes /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP  --sdk-auth > gh-secret.json
export clientID=$(cat gh-secret.json | jq -r .clientId)
export PASSWORD=$(cat gh-secret.json | jq -r .clientSecret)
export TENANT_ID=$(cat gh-secret.json | jq -r .tenantId)
export SUB_ID=$(cat gh-secret.json | jq -r .subscriptionId)

# Set azure policy to allow for key vault and access policy creation in this resource group
# echo "Setting Azure Policy to allow for Key Vault and Access Policy creation in this resource group..."
# az policy assignment create --name 'Deploy Key Vault' --scope /subscriptions/$SUB_ID/resourceGroups/$RESOURCE_GROUP --policy /providers/Microsoft.Authorization/policyDefinitions/4fae8e6a-5c83-4f35-9f8d-9c3838c5ed97 --params "{\"allowedLocations\":{\"value\":[\"$LOCATION\"]}}"

# Create 6 character GUID - no dashes and append it to the vault name
export GU=$(uuidgen)
export GUI=$(echo $GU | tr -d "-")
export GUID=${GUI:0:6}
export AKV=$CUSTOMER_NAME$GUID


echo "Creating Azure Key Vault..."
az keyvault create --name $AKV --resource-group $RESOURCE_GROUP --location $LOCATION
# Create a certificate in the keyvault
# Create a certificate in the keyvault
echo "Creating a certificate in the keyvault..."
az keyvault certificate create --vault-name $AKV --name myCert --policy "$(az keyvault certificate get-default-policy)"


sleep 5

az role assignment create --role "Key Vault Secrets Officer"  \
--assignee $clientID \
--scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$AKV

az role assignment create --role "Key Vault Secrets Officer"  \
--assignee $clientID \
--scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP


echo "az login --service-principal --username $clientID --password $PASSWORD --tenant $TENANT_ID" > $CUSTOMER-login.txt

