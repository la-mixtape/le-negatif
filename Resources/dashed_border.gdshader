shader_type canvas_item;

uniform vec4 color : source_color = vec4(1.0, 0.8, 0.2, 1.0);
uniform float line_width : hint_range(0.0, 50.0) = 4.0;
uniform float dash_size : hint_range(1.0, 50.0) = 20.0;
uniform float gap_size : hint_range(1.0, 50.0) = 10.0;
uniform float velocity : hint_range(-10.0, 10.0) = 2.0;

// On ajoute cette variable pour recevoir la taille exacte depuis le script
uniform vec2 rect_size = vec2(100.0, 100.0); 

void fragment() {
    // On calcule la position en pixels réels en multipliant les UV (0 à 1) par la taille
    vec2 pixel_pos = UV * rect_size;
    
    // Distance par rapport aux 4 bords
    float dist_left = pixel_pos.x;
    float dist_top = pixel_pos.y;
    float dist_right = rect_size.x - pixel_pos.x;
    float dist_bottom = rect_size.y - pixel_pos.y;
    
    // On cherche la distance la plus courte vers un bord
    float dist_edge = min(min(dist_left, dist_right), min(dist_top, dist_bottom));
    
    // Si on est à l'intérieur (plus loin du bord que l'épaisseur du trait), c'est transparent
    if (dist_edge > line_width) {
        COLOR = vec4(0.0);
    } else {
        // Logique d'animation des tirets ("Marching Ants")
        float perimeter_pos = 0.0;
        
        // On détermine sur quel côté on se trouve pour faire avancer les tirets dans le bon sens
        if (dist_top <= line_width) {
            perimeter_pos = pixel_pos.x; // Haut : gauche vers droite
        } else if (dist_right <= line_width) {
            perimeter_pos = rect_size.x + pixel_pos.y; // Droite : haut vers bas
        } else if (dist_bottom <= line_width) {
            perimeter_pos = rect_size.x + rect_size.y + (rect_size.x - pixel_pos.x); // Bas : droite vers gauche
        } else {
            perimeter_pos = rect_size.x * 2.0 + rect_size.y + (rect_size.y - pixel_pos.y); // Gauche : bas vers haut
        }
        
        float total_dash = dash_size + gap_size;
        float anim_pos = perimeter_pos - (TIME * velocity * 20.0); // Le "-" inverse le sens pour tourner horaire
        
        if (mod(anim_pos, total_dash) < dash_size) {
            COLOR = color;
        } else {
            COLOR = vec4(0.0); // Espace vide entre tirets
        }
    }
}