#!/usr/bin/env bash

az group delete --name RG-TaskManager --yes --no-wait
az group delete --name NetworkWatcherRG --yes --no-wait

