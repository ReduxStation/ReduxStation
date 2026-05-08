#!/bin/bash

# Project dependencies file
# Final authority on what's required to fully build the project.

# BYOND version — used by the root Dockerfile to construct the download URL:
#   https://www.byond.com/download/build/$BYOND_MAJOR/$BYOND_MAJOR.$BYOND_MINOR_byond_linux.zip
export BYOND_MAJOR=516
export BYOND_MINOR=1680

# rust_g git tag
export RUST_G_VERSION=0.4.2

# BSQL git tag
export BSQL_VERSION=v1.4.0.0

# Node version (reference only — Docker uses the node:20 image directly)
export NODE_VERSION=12

# PHP version
export PHP_VERSION=7.2

# SpacemanDMM git tag
export SPACEMAN_DMM_VERSION=suite-1.11

export QUICKWRITE_TAG=98b5183e3da5d14e59c38030a9b6824a615c8260
