extends Resource
class_name InvestigationDef

## Root investigation definition — holds metadata and the master deduction list
## shared across the root scene and all sub-scenes in the investigation tree.

## Unique identifier for this investigation
@export var investigation_id: String = ""

## Human-readable name shown in the selection menu
@export var display_name: String = ""

## Short description for the selection menu
@export_multiline var description: String = ""

## The root scene path for this investigation
@export_file("*.tscn") var root_scene: String = ""

## Thumbnail texture for the selection menu
@export var vignette_texture: Texture2D

## Master list of all deductions across every sub-scene in this investigation
@export var deductions: Array[DeductionDef] = []
