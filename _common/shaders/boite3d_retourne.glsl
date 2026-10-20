// boite3d_retourne.glsl : boîte 3D construite avec les scraps existants (face = thumbnail, dos = boxback, tranche = bord de la face),
// d après boite24.glsl (Hyperbat). Un élément par face, même réglages : u_mode 0 face, 1 dos, 2 tranche (unie, u_spine_color).
// Tous les éléments ont la MÊME taille (format de boîte du système) : jaquette, dos et logo sont ajustés à la face.
// u_mode 3.2 = logo du jeu couché sur la tranche (élément portant {game:marquee}).
// u_phase (animé par la vue, 0 -> 1 en boucle) fait pivoter la boîte pour montrer le dos puis revenir.
#if defined(VERTEX)

#if __VERSION__ >= 130
#define COMPAT_VARYING out
#define COMPAT_ATTRIBUTE in
#define COMPAT_TEXTURE texture
#else
#define COMPAT_VARYING varying
#define COMPAT_ATTRIBUTE attribute
#define COMPAT_TEXTURE texture2D
#endif

uniform mat4 MVPMatrix;
COMPAT_ATTRIBUTE vec2 VertexCoord;
COMPAT_ATTRIBUTE vec2 TexCoord;
COMPAT_ATTRIBUTE vec4 COLOR;

COMPAT_VARYING vec2 v_tex;
COMPAT_VARYING vec4 v_col;

void main(void) {
    gl_Position = MVPMatrix * vec4(VertexCoord.xy, 0.0, 1.0);
    v_tex = TexCoord;
    v_col = COLOR;
}

#elif defined(FRAGMENT)

#if __VERSION__ >= 130
#define COMPAT_VARYING in
#define COMPAT_TEXTURE texture
out vec4 FragColor;
#else
#define COMPAT_VARYING varying
#define FragColor gl_FragColor
#define COMPAT_TEXTURE texture2D
#endif

#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif

uniform sampler2D u_tex;
uniform float u_angle;
uniform float u_phase;   // 0..1 animé par la vue (shader.u_phase) : retournement face -> dos -> face ; 0 = angle fixe
uniform float u_thickness;
uniform float u_mode;
uniform float u_pitch;
uniform float u_logo_scale;
uniform float u_shiny;
uniform vec4 u_cap_color;
uniform vec4 u_spine_color;   // tranche unie (blanche par défaut) au lieu du bord de la jaquette

COMPAT_VARYING vec2 v_tex;
COMPAT_VARYING vec4 v_col;

// =====================
// ANTIALIAS GLOBAL
// =====================
float AA;
float antialias(float edge, float value) {
    return smoothstep(edge + AA, edge - AA, value);
}

// Fonction pour simuler le reflet plastique
float getSpecular(float angle, vec2 uv) {
    float lightPos = 0.5; 
    float refAngle = angle + lightPos;
    float spec = pow(max(0.0, cos(refAngle)), 10.0);
    float sheen = smoothstep(0.4, 0.6, sin(angle + uv.x * 3.0 + uv.y * 2.0));
    return (spec + sheen * 0.2) * u_shiny; 
}

void main(void) {

    float internalScale = 0.6;
    vec2 uv = (v_tex - 0.5) / internalScale;
    
    // AA Isotropique Ultra-Smooth
    float fwX = fwidth(uv.x);
    float fwY = fwidth(uv.y);
    AA = length(vec2(fwX, fwY)) * 3.0;
    AA = max(AA, 0.0025);

    // =====================
    // CORRECTION AUTOMATIQUE DU RATIO
    // =====================
    // Détecte le ratio de l'image originale et du conteneur.
    // Ne touche PAS aux UV/géométrie. On calcule un facteur de correction
    // qui sera appliqué uniquement aux coordonnées de texture lors du sampling.
    float ratioFixX = 1.0; // Correction horizontale pour le sampling texture
    float ratioFixY = 1.0; // Correction verticale pour le sampling texture
    
    #if __VERSION__ >= 130
        ivec2 tSize = textureSize(u_tex, 0);
        float imgRatio = float(tSize.x) / float(tSize.y);
        
        // Ratio du conteneur (rectangle de rendu imposé par <size>)
        float containerRatio = fwidth(v_tex.y) / fwidth(v_tex.x);
        
        // Si l'image et le conteneur n'ont pas le même ratio,
        // ES a étiré/écrasé l'image. On calcule la correction.
        if (imgRatio > containerRatio * 1.02) {
            // Image plus large que le conteneur → ES l'a écrasée en X
            // On doit lire une sous-zone en X de la texture
            ratioFixX = 1.0;
        } else if (imgRatio < containerRatio * 0.98) {
            // Image plus haute que le conteneur → ES l'a écrasée en Y
            ratioFixY = 1.0;
        }
    #endif

    // retournement : face jusqu'à 35 % du cycle, demi-tour jusqu'à 50 %, dos jusqu'à 85 %, demi-tour jusqu'à 100 %
    float angDeg = u_angle;
    if (u_phase > 0.0) {
        float p = fract(u_phase);
        angDeg += 180.0 * (smoothstep(0.35, 0.5, p) + smoothstep(0.85, 1.0, p));
    }
    float radAngle = radians(angDeg);
    // à plat au repos (face ou dos de pleine face) : la plongée n apparaît que pendant la rotation
    float P = u_pitch * abs(sin(radians(angDeg)));   // nulle de face et de dos (image plate), présente dès que la boîte est tournée
    if (u_mode > 0.5 && u_mode < 1.5) radAngle += 3.14159265;
    
    float cosA = cos(radAngle);
    float sinA = sin(radAngle);
    float halfThick = u_thickness * 0.5;

    float depthZ = 0.0;
    float texX = 0.5;
    float alphaX = 0.0;
    bool isFaceArea = false;

    // =====================
    // GÉOMÉTRIE HORIZONTALE (inchangée)
    // =====================
    if (u_mode < 0.5) { // FRONT
        if (cosA > 0.0) {
            float localX = (uv.x - halfThick * sinA) / cosA;
            alphaX = antialias(0.5, abs(localX));
            depthZ = -localX * sinA + halfThick * cosA;
            texX = localX + 0.5;
            isFaceArea = true;
        }
    }
    else if (u_mode > 1.5) { // SPINE
        float side = (sinA >= 0.0) ? 0.5 : -0.5;
        if (abs(sinA) > 0.001) {
            float localZ = (uv.x + side * cosA) / sinA;
            alphaX = antialias(halfThick, abs(localZ));
            depthZ = side * sinA + localZ * cosA;
            float rawTexX = (localZ / u_thickness) + 0.5;
            texX = (sinA >= 0.0) ? rawTexX : 1.0 - rawTexX;
            isFaceArea = true;
        }
    }
    else { // BACK
        if (cosA > 0.0) {
            float localX = (uv.x - halfThick * sinA) / cosA;
            alphaX = antialias(0.5, abs(localX));
            depthZ = -localX * sinA + halfThick * cosA;
            texX = localX + 0.5;
            isFaceArea = true;
        }
    }

    // --- 2. GÉOMÉTRIE VERTICALE ---
    float EPSILON = 0.002;
    float yOffset = depthZ * P;
    float faceTop = 0.5 + yOffset;
    float faceBottom = -0.5 + yOffset;
    float edgeSoftness = AA * 1.5;
    
    // --- 3. RENDU EN COUCHES ---
    vec4 color = vec4(0.0);
    
    float baseLight = (u_mode > 1.5) ? abs(sinA) : abs(cosA);
    float light = 0.5 + 0.5 * baseLight; 
    
    // arête face / couvercle : bord NET du côté où le couvercle est visible (un bord adouci laissait voir le fond)
    // choisi d après le réglage (u_pitch) et non la plongée du moment (P) : sinon le bord basculait net / adouci
    // quand la boîte revient à plat en fin de rotation -> clignotement en haut de la jaquette
    float douxHaut = (u_pitch < -0.001) ? 0.0 : edgeSoftness;
    float douxBas  = (u_pitch >  0.001) ? 0.0 : edgeSoftness;
    float alphaY = ((douxBas > 0.0) ? smoothstep(faceBottom - douxBas, faceBottom + douxBas, uv.y) : step(faceBottom, uv.y))
                 * ((douxHaut > 0.0) ? smoothstep(faceTop + douxHaut, faceTop - douxHaut, uv.y) : step(uv.y, faceTop));
    
    // ====== COUCHE 1 : COUVERCLES (TOP/BOTTOM CAP) ======
    bool showTop = (P < -0.001 && uv.y > faceTop - EPSILON);
    bool showDown = (P > 0.001 && uv.y < faceBottom + EPSILON);

    if (u_mode < 2.5 && (showTop || showDown)) {
        float yCapLimit = (uv.y > 0.0) ? 0.5 : -0.5;
        float pitchSafe = P + sign(P) * 0.0000001;
        float B = (uv.y - yCapLimit) / pitchSafe;
        
        float capX = uv.x * cosA - B * sinA;
        float capZ = uv.x * sinA + B * cosA;

        float capAA = AA;
        float edgeAlphaX = smoothstep(0.501 + capAA, 0.501 - capAA, abs(capX));
        float edgeAlphaZ = step(abs(capZ), halfThick);   // arête avec la face et la tranche : nette
        float capAlpha = edgeAlphaX * edgeAlphaZ;

        if (capAlpha > 0.001) {
            float capTexX = capX + 0.5;
            float capTexY = (capZ / u_thickness) + 0.5;
            
            // Appliquer la correction de ratio au sampling du cap
            capTexX = (capTexX - 0.5) / ratioFixX + 0.5;
            capTexY = (capTexY - 0.5) / ratioFixY + 0.5;
            
            vec2 capTexCoord = vec2(clamp(capTexX, 0.0, 1.0), clamp(capTexY, 0.01, 0.99));
            vec4 rawCapColor = COMPAT_TEXTURE(u_tex, capTexCoord);
            
            vec3 capBaseColor = (u_cap_color.a > 0.0) ? u_cap_color.rgb : vec3(0.95);

            float capLight = (uv.y > 0.0) ? 0.35 : 0.15;
            capLight *= (0.65 + 0.35 * abs(cosA));
            
            float capSpec = (u_shiny > 0.01) ? 0.2 * u_shiny * abs(cosA) : 0.0;
            
            vec3 finalCapRGB = capBaseColor * capLight + vec3(capSpec);
            color = vec4(finalCapRGB, capAlpha);
        }
    }
    
    // ====== COUCHE 2 : TEXTURE DE LA FACE ======
    if (uv.y <= faceTop + EPSILON && uv.y >= faceBottom - EPSILON) {
        float yPos = (uv.y - yOffset) + 0.5;
        vec2 finalTexCoord;

        if (u_mode > 2.5) {
            float startY, endY;
            bool rotate = false;
            if (u_mode < 3.15) { startY=0.80; endY=0.98; rotate=false; }
            else if (u_mode < 3.25) { startY=0.15; endY=0.85; rotate=true; }
            else { startY=0.02; endY=0.20; rotate=false; }
            
            float localY = (yPos - startY) / (endY - startY);
            float scale = (u_logo_scale > 0.01) ? u_logo_scale : 1.0;
            float finalY = (localY - 0.5) / scale + 0.5;
            
            if (finalY >= 0.0 && finalY <= 1.0) {
                if (rotate) finalTexCoord = vec2(finalY, 1.0 - texX);
                else finalTexCoord = vec2(texX, finalY);
            } else {
                discard; 
            }
        } else if (u_mode > 1.5) {
            finalTexCoord = vec2(0.01 + texX * 0.04, clamp(yPos, 0.0, 1.0));
        } else {
            // Faces (Modes 0.0/1.0) — Appliquer la correction de ratio ici
            float corrTexX = (texX - 0.5) / ratioFixX + 0.5;
            float corrTexY = (yPos - 0.5) / ratioFixY + 0.5;
            finalTexCoord = vec2(corrTexX, clamp(corrTexY, 0.0, 1.0));
            
            // Si les coordonnées corrigées sortent de [0,1], le pixel est hors image
            if (corrTexX < 0.0 || corrTexX > 1.0 || corrTexY < 0.0 || corrTexY > 1.0) {
                discard;
            }
        }
        
        vec4 texColor = COMPAT_TEXTURE(u_tex, finalTexCoord);
        if (u_mode > 1.5 && u_mode < 2.5) texColor = (u_spine_color.a > 0.0) ? vec4(u_spine_color.rgb, 1.0) : vec4(0.95, 0.95, 0.95, 1.0);
        
        // --- REFLET SHINY SUR LA FACE ---
        float spec = 0.0;
        if (u_shiny > 0.01) {
            bool isSpine = (u_mode > 1.5);
            float faceAngle = isSpine ? radAngle + 1.5708 : radAngle;
            spec = getSpecular(faceAngle, uv);
            spec *= abs(sin(radians(angDeg)));   // pas de reflet de face : image plate
        }

        vec3 finalRGB = texColor.rgb * light + vec3(spec);
        vec4 litTexColor = vec4(finalRGB, texColor.a * alphaX * alphaY);
        
        color.rgb = mix(color.rgb, litTexColor.rgb, litTexColor.a);
        color.a = max(color.a, litTexColor.a);
    }

    if (color.a <= 0.0) discard;
    FragColor = color * v_col;
}
#endif
