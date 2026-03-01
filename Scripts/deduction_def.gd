extends Resource
class_name DeductionDef

## Unique identifier for this deduction (matches clue.deduction_id)
@export var deduction_id: String = ""

## Guiding question displayed to the player for this deduction
@export var question: String = ""

## Image displayed on screen when this deduction is completed
@export var image: Texture2D

## If true, this deduction is not required for investigation completion
@export var optional: bool = false

## Availability condition: deduction is available only when this evaluates to true.
## If null, the deduction is always available.
@export var availability_condition: DeductionExpression = null
