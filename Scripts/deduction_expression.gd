@tool
extends Resource
class_name DeductionExpression

## A recursive boolean expression evaluated against completed deductions.
## Use the Type enum to switch between a leaf (single deduction check)
## and a compound expression (operator + two sub-expressions).

enum Type { DEDUCTION, EXPRESSION }
enum Operator { AND, OR, XOR }

const _EMPTY_LABEL := "(None)"

## Whether this node checks a single deduction or combines two expressions
@export var type: Type = Type.DEDUCTION:
	set(value):
		type = value
		notify_property_list_changed()

## Backing stores (exposed conditionally via _get_property_list)
var _deduction_id: String = ""
var _operator: Operator = Operator.AND
var _left_expression: DeductionExpression = null
var _right_expression: DeductionExpression = null


func _set(property: StringName, value: Variant) -> bool:
	match property:
		&"deduction_id":
			_deduction_id = "" if str(value) == _EMPTY_LABEL else str(value)
			return true
		&"operator":
			_operator = value as Operator
			return true
		&"left_expression":
			_left_expression = value
			return true
		&"right_expression":
			_right_expression = value
			return true
	return false


func _get(property: StringName) -> Variant:
	match property:
		&"deduction_id":
			if Engine.is_editor_hint() and _deduction_id.is_empty():
				return _EMPTY_LABEL
			return _deduction_id
		&"operator":
			return _operator
		&"left_expression":
			return _left_expression
		&"right_expression":
			return _right_expression
	return null


func _get_property_list() -> Array[Dictionary]:
	var props: Array[Dictionary] = []

	if type == Type.DEDUCTION:
		var hint_string := _EMPTY_LABEL
		if Engine.is_editor_hint():
			var ids := _get_all_deduction_ids()
			if ids.size() > 0:
				hint_string = _EMPTY_LABEL + "," + ",".join(ids)
		props.append({
			"name": "deduction_id",
			"type": TYPE_STRING,
			"hint": PROPERTY_HINT_ENUM,
			"hint_string": hint_string,
			"usage": PROPERTY_USAGE_DEFAULT,
		})
	else:
		props.append({
			"name": "operator",
			"type": TYPE_INT,
			"hint": PROPERTY_HINT_ENUM,
			"hint_string": "AND,OR,XOR",
			"usage": PROPERTY_USAGE_DEFAULT,
		})
		props.append({
			"name": "left_expression",
			"type": TYPE_OBJECT,
			"hint": PROPERTY_HINT_RESOURCE_TYPE,
			"hint_string": "DeductionExpression",
			"usage": PROPERTY_USAGE_DEFAULT,
		})
		props.append({
			"name": "right_expression",
			"type": TYPE_OBJECT,
			"hint": PROPERTY_HINT_RESOURCE_TYPE,
			"hint_string": "DeductionExpression",
			"usage": PROPERTY_USAGE_DEFAULT,
		})

	return props


func _get_all_deduction_ids() -> PackedStringArray:
	"""Return deduction IDs from the parent InvestigationDef, excluding the owner."""
	var ids := PackedStringArray()
	var context := _find_parent_context()
	if not context["inv_def"]:
		return ids
	var exclude: String = context["owner_id"]
	for ded in context["inv_def"].deductions:
		if ded is DeductionDef and not ded.deduction_id.is_empty():
			if ded.deduction_id != exclude and not ids.has(ded.deduction_id):
				ids.append(ded.deduction_id)
	return ids


func _find_parent_context() -> Dictionary:
	"""Find the InvestigationDef and owning DeductionDef's ID for this expression."""
	var result := { "inv_def": null, "owner_id": "" }
	var dir := DirAccess.open("res://data/investigations/")
	if not dir:
		return result
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if file.ends_with(".tres"):
			var res = load("res://data/investigations/" + file)
			if res is InvestigationDef:
				for ded in res.deductions:
					if ded is DeductionDef and ded.availability_condition != null:
						if _expr_contains_self(ded.availability_condition):
							result["inv_def"] = res
							result["owner_id"] = ded.deduction_id
							return result
		file = dir.get_next()
	return result


func _expr_contains_self(expr: DeductionExpression) -> bool:
	"""Recursively check if an expression tree contains this instance."""
	if expr == self:
		return true
	if expr._left_expression and _expr_contains_self(expr._left_expression):
		return true
	if expr._right_expression and _expr_contains_self(expr._right_expression):
		return true
	return false


func is_leaf() -> bool:
	return type == Type.DEDUCTION


func evaluate(completed: Dictionary) -> bool:
	"""Evaluate this expression against a dictionary of completed deduction IDs."""
	if is_leaf():
		if _deduction_id.is_empty():
			return true
		return completed.get(_deduction_id, false)

	if not _left_expression or not _right_expression:
		push_warning("DeductionExpression: compound node missing left or right child")
		return true

	var left_val := _left_expression.evaluate(completed)
	var right_val := _right_expression.evaluate(completed)

	match _operator:
		Operator.AND:
			return left_val and right_val
		Operator.OR:
			return left_val or right_val
		Operator.XOR:
			return left_val != right_val

	return true
