# Wilkerstat Application Platform

## Introduction

This app was created to help processing Wilkerstat data, be it images or other geographic information system

## Current Feature

- QR-based rename
- Auto rotate
- Change image DPI
- Create world file (based on [Digitasi Repo](https://github.com/devara46/digitasi/tree/main))
  - Default settings
    - 5% Expand Percentage
    - 200 DPI
    - 3307 x 2338 image dimensions
    - .jgw world file extension extension
  - Advanced Settings
    - Expand Percentage : 0% - 50%
    - DPI : 50 - 600
    - Manually modify dimensions
    - World file extension : .jgw; .pgw; .tfw; .gfw
- Organize files by ID
- Off-area tagging
- Evaluate polygon to SiPW
  - Name comparison
  - Records only in polygon
  - Records only in SiPW
  - Duplicated IDs
  - Records with no polygon
  - Customized overlap with different ID identification
- Reports generator
  - Rekapitulasi Jumlah SLS/Non-SLS/Sub-SLS
  - Rekapitulasi Rata-rata Muatan
  - Rekapitulasi Wilayah Konsentrasi Ekonomi per Dominan 

## Future Plan

- improve UI
- add reproject crs function
