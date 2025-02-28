#!/bin/bash

# Load environment variables from .env file
export $(grep -v '^#' .env | xargs)

# Add Hardhat to PATH
export PATH=$PATH:/path/to/hardhat

# Source the Hardhat config file to apply configurations
source /Users/cpope/trading_bot_v3/hardhat.config.js