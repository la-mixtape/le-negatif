# Le Negatif

A 2D detective/puzzle investigation game built with Godot Engine 4.6. Players examine scenes, select interactive objects, and combine them to form logical deduction chains.

## Project Overview

Le Negatif is an investigation game where players:
- Explore detailed scenes by panning and zooming
- Click on interactive objects to examine them
- Combine objects to form deduction chains
- Solve mysteries through logical reasoning

## Technology Stack

- **Engine:** Godot 4.6 (Mobile renderer)
- **Language:** GDScript
- **Shaders:** GLSL
- **Resolution:** 1920x1080
- **Rendering:** DirectX 12 (Windows), 2x MSAA

## Project Structure

```
le-negatif/
├── Assets/Images/          # Game images (investigation backgrounds)
├── Resources/              # Shaders and reusable resources
│   └── dashed_border.gdshader
├── Scenes/                 # .tscn scene files
│   ├── MainMenu.tscn
│   ├── InvestigationTemplate.tscn
│   ├── InvestigationHUD.tscn
│   └── DebugMenu.tscn
├── Scripts/                # .gd script files
│   ├── GameManager.gd
│   ├── InvestigationTemplate.gd
│   ├── InteractiveObject.gd
│   ├── InvestigationHUD.gd
│   ├── MainMenu.gd
│   └── DebugMenu.gd
└── project.godot          # Main Godot configuration
```

## Major Components

### 1. GameManager (Global Singleton)
**File:** `Scripts/GameManager.gd`

Central game state manager that:
- Tracks discovered deductions across scenes
- Manages global game state
- Provides the `add_deduction()` method for progression

### 2. InvestigationTemplate (Core Gameplay)
**Files:** `Scripts/InvestigationTemplate.gd`, `Scenes/InvestigationTemplate.tscn`

The heart of the game, handling:
- **Camera Controls:** Pan (QZSD/arrows/right-click drag) and smooth zoom with mouse wheel
- **Selection System:** Tracks up to 4 selected objects simultaneously
- **Deduction Validation:** Checks if selected objects form valid chains
- **State Management:** Success, failure, and "already found" states with appropriate feedback

### 3. InteractiveObject (Clickable Objects)
**File:** `Scripts/InteractiveObject.gd`

Base class for all clickable investigation objects with:
- **State Machine:** IDLE → HOVER → SELECTED → COMPLETED
- **Visual Feedback:** Animated dashed border on hover (using custom shader)
- **Event Handling:** Emits `object_clicked` signal and tracks mouse interactions

### 4. InvestigationHUD (User Interface)
**Files:** `Scripts/InvestigationHUD.gd`, `Scenes/InvestigationHUD.tscn`

Manages the overlay showing selected clues:
- **Card Animation:** Dramatic 0.6s pause, then smooth flight from object to slot
- **Visual Polish:** Random rotation, floating "breathing" effect
- **Failure Feedback:** Shake animation with 10 iterations

### 5. Custom Shader
**File:** `Resources/dashed_border.gdshader`

Creates the animated "marching ants" border effect for hovering objects with configurable speed and style.

### 6. MainMenu
**Files:** `Scripts/MainMenu.gd`, `Scenes/MainMenu.tscn`

Entry point with buttons for:
- New Game
- Continue (disabled - save system not yet implemented)
- Options (placeholder)
- Credits (placeholder)
- Quit

## Gameplay Flow

1. Player starts from **MainMenu**
2. Enters **Investigation Scene** with background image
3. **Explores** the scene:
   - Pan with QZSD/Arrow keys or right-click drag
   - Zoom with mouse wheel or E/A keys
   - Objects highlight on hover with animated dashed border
4. **Selects objects** by clicking (up to 4 selections)
   - Objects animate into HUD slots
   - Cropped textures created from background
5. System **validates** selections:
   - ✅ Valid chain → Success → Objects marked completed
   - ⏳ Partial match → Keep going
   - 🔄 Already found → Neutral feedback
   - ❌ Invalid → Shake animation → Reset
6. Repeat until all deduction chains are discovered

## Controls

### Camera
- **Pan:** QZSD / Arrow keys / Right-click drag
- **Zoom In:** Mouse wheel up / E key
- **Zoom Out:** Mouse wheel down / A key

### Interaction
- **Select Object:** Left-click on interactive object
- **Debug Menu:** Escape key (development mode)

## Features

### Implemented
- Core investigation mechanics
- Object selection and validation system
- Advanced camera controls with smooth zoom
- Polished HUD animations
- Hover effects with custom shaders
- Debug menu for testing

### Planned
- Drag & drop system
- Save/load system
- Options menu
- Credits screen
- Additional investigation scenes

## Development

### Debug Mode
Press `Escape` to toggle the debug menu during gameplay.

### Adding New Interactive Objects
1. Create a new node inheriting from `InteractiveObject`
2. Define the object's crop boundaries (manual or polygon-based)
3. Add the object name to valid deduction chains in `InvestigationTemplate.gd`

### Defining Deduction Chains
Edit the `valid_chains` array in `InvestigationTemplate.gd`:
```gdscript
valid_chains = [
    ["ObjectA", "ObjectB"],
    ["ObjectB", "ObjectC"]
]
```

## Language

The project is developed in French, with French variable names, comments, and debug messages.

## License

[Add your license here]
