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

#ifdef GL_ES
#define COMPAT_PRECISION mediump
#else
#define COMPAT_PRECISION
#endif

uniform   mat4 MVPMatrix;
COMPAT_ATTRIBUTE vec2 VertexCoord;
COMPAT_ATTRIBUTE vec2 TexCoord;
COMPAT_ATTRIBUTE vec4 COLOR;
COMPAT_VARYING   vec2 v_tex;
COMPAT_VARYING   vec4 v_col;
COMPAT_VARYING   vec2 v_pos;

void main(void)                                     
{                                                   
    gl_Position = MVPMatrix * vec4(VertexCoord.xy, 0.0, 1.0);
    v_tex       = TexCoord;                           
    v_col       = COLOR;                           
    v_pos       = VertexCoord;
}

#elif defined(FRAGMENT)

// fwidth() requis pour l'antialiasing (GLSL ES 1.0)
#extension GL_OES_standard_derivatives : enable

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
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
#define COMPAT_PRECISION mediump
#else
#define COMPAT_PRECISION
#endif

// ─────────────────────────────────────────────────────────────
//  Réglages rapides (modifiables directement ici)
// ─────────────────────────────────────────────────────────────
// Couleur du plastique du boîtier (noir DVD classique)
#define CASE_COLOR        vec3(0.045, 0.045, 0.052)
// 1 = la couleur du boîtier vient de l'uniform borderColor (XML), si son alpha > 0
// (ex. bleu pour un boîtier Blu-ray, blanc, vert...). Sinon : CASE_COLOR ci-dessus.
// 0 = toujours CASE_COLOR.
#define USE_BORDER_COLOR  1
// Intensité des reflets (0.0 = mat, 1.0 = normal, 1.5 = très brillant)
#define GLOSS             1.0
// Passer à 1 si l'éclairage semble venir du bas au lieu du haut
#define FLIP_LIGHT_Y      0
// ─────────────────────────────────────────────────────────────

COMPAT_VARYING   vec4      v_col;
COMPAT_VARYING   vec2      v_tex;
COMPAT_VARYING   vec2      v_pos;

uniform sampler2D u_tex;
uniform vec2 textureSize;
uniform vec2 outputSize;
uniform vec2 outputOffset;

// Épaisseur du liseré noir du boîtier (haut / bas / droite).
// 0 = automatique (~3 mm sur un boîtier de 135 mm de large).
// < 1 : fraction de la hauteur, >= 1 : pixels (comme avant).
uniform float borderSize;
uniform vec4  borderColor;          // seulement si USE_BORDER_COLOR = 1

uniform float cornerRadius;         // 0 = automatique
uniform float innerShadowSize;      // ombre portée par le rebord sur l'image, 0 = automatique
uniform vec4  innerShadowColor;     // alpha 0 = noir 55%
uniform float outerShadowSize;      // ombre portée du boîtier (0 = aucune)
uniform vec4  outerShadowColor;     // alpha 0 = noir 70%
uniform float saturation;
uniform bool   bilinearFiltering;

// Forme du boîtier :
//   0 = DVD classique (charnière large à gauche, rainure)   <- défaut
//   1 = slim console (Wii U, Switch, PS4, Xbox...) : cadre fin, coins très arrondis, plastique brillant
uniform int    caseType;

vec4 sampleTexture(sampler2D tex, vec2 texCoord) {
    return COMPAT_TEXTURE(tex, texCoord);
}

float getComputedValue(float value, float defaultValue) {
    if (value == 0.0)
        return defaultValue;
    if (value < 1.0)
        return abs(outputSize.y) * value;
    return value;
}

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// Distance signée à un rectangle arrondi (négative à l'intérieur)
float sdRoundRect(vec2 p, vec2 c, vec2 halfSize, float r) {
    vec2 q = abs(p - c) - halfSize + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Normale 2D sortante (direction du gradient du SDF) d'un rectangle arrondi
vec2 rrNormal(vec2 p, vec2 c, vec2 halfSize, float r) {
    vec2 d = p - c;
    vec2 q = abs(d) - halfSize + r;
    vec2 n;
    if (q.x > 0.0 && q.y > 0.0)
        n = normalize(q);
    else
        n = (q.x > q.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
    return n * vec2(d.x < 0.0 ? -1.0 : 1.0, d.y < 0.0 ? -1.0 : 1.0);
}

void main(void)
{
    // Si on sort prématurément, il faut quand même appliquer v_col
    if (sampleTexture(u_tex, vec2(1.0)).a < 0.3 || sampleTexture(u_tex, vec2(0.0)).a < 0.3) {
        FragColor = sampleTexture(u_tex, v_tex) * v_col;
        return;
    }

    vec2  size    = abs(outputSize);
    float W       = size.x;
    float H       = size.y;
    float minSide = min(W, H);

    // ── Dimensions du boîtier (en pixels) ──────────────────────
    // Paramètres propres à chaque forme de boîtier (ajouter un `else if` pour une nouvelle forme)
    float rimAuto, hingeK, radK, rInK, rollBase, glossK, grooveOn, spineOn, lipK;
    if (caseType == 1) {            // slim console : cadre sur 3 côtés, simple bande de dos à gauche
        rimAuto = 0.026; hingeK = 0.16; radK = 1.2; rInK = 0.3;
        rollBase = 0.55; glossK = GLOSS * 1.3; grooveOn = 0.0;
        spineOn = 1.0;   lipK = 0.3;
    } else {                        // 0 : DVD
        rimAuto = 0.022; hingeK = 2.4; radK = 0.8; rInK = 0.1;
        rollBase = 0.45; glossK = GLOSS;       grooveOn = 1.0;
        spineOn = 0.0;   lipK = 0.6;
    }

    float os    = getComputedValue(outerShadowSize, 0.0);
    float rim   = min(getComputedValue(borderSize, rimAuto * minSide), 0.15 * minSide);
    float hinge = rim * hingeK;                    // côté charnière (gauche)
    float rOut  = min(getComputedValue(cornerRadius, radK * rim), 0.5 * minSide);
    float rIn   = rInK * rim;                      // coins de la fenêtre
    float lipSh = getComputedValue(innerShadowSize, lipK * rim);

    // ── Rétrécissement de l'image : elle remplit la "fenêtre" du boîtier ──
    vec2 decal = vec2((os + hinge) / W, (os + rim) / H);   // gauche, haut/bas
    float decalR = (os + rim) / W;                          // droite
    decal  = min(decal,  vec2(0.45));
    decalR = min(decalR, 0.45);

    float denomX = max(1.0 - decal.x - decalR, 0.02);
    float denomY = max(1.0 - 2.0 * decal.y,    0.02);

    vec2 adjustedTexCoord = vec2(
        (v_tex.x - decal.x) / denomX,
        (v_tex.y - decal.y) / denomY
    );

    vec4 sampledColor = sampleTexture(u_tex, adjustedTexCoord);

    if (bilinearFiltering)
    {
        vec2 texelSize = 1.0 / textureSize;
        vec2 uv_coord = adjustedTexCoord;
        vec2 f = fract(uv_coord);

        vec4 texel00 = sampleTexture(u_tex, uv_coord);
        vec4 texel10 = sampleTexture(u_tex, uv_coord + vec2(texelSize.x, 0.0));
        vec4 texel01 = sampleTexture(u_tex, uv_coord + vec2(0.0, texelSize.y));
        vec4 texel11 = sampleTexture(u_tex, uv_coord + texelSize);

        sampledColor = mix(
            mix(texel00, texel10, f.x),
            mix(texel01, texel11, f.x),
            f.y
        );
    }

    if (saturation != 1.0) {
        vec3 gray = vec3(dot(sampledColor.rgb, vec3(0.34, 0.55, 0.11)));
        vec3 blend = mix(gray, sampledColor.rgb, saturation);
        sampledColor = vec4(blend, sampledColor.a);
    }

    sampledColor *= v_col;

    // ── Géométrie (SDF) ─────────────────────────────────────────
    vec2 lp = v_pos - outputOffset;                // position en pixels dans la sortie

    vec2 caseCenter = size * 0.5;
    vec2 caseHalf   = size * 0.5 - os;
    float dCase = sdRoundRect(lp, caseCenter, caseHalf, rOut);

    vec2 winMin    = vec2(os + hinge, os + rim);
    vec2 winMax    = vec2(W - os - rim, H - os - rim);
    vec2 winCenter = 0.5 * (winMin + winMax);
    vec2 winHalf   = 0.5 * (winMax - winMin);
    float dWin = sdRoundRect(lp, winCenter, winHalf, rIn);

    float aa = max(fwidth(dCase), 1.0);

    if (dCase > aa && os <= 0.0) {
        FragColor = vec4(0.0);
        return;
    }

    // ── Lumière : venue du haut à gauche ────────────────────────
    vec2 L = normalize(vec2(-0.55, -0.85));
    vec2 np = lp / size;                           // position normalisée 0..1
#if FLIP_LIGHT_Y
    L.y  = -L.y;
    np.y = 1.0 - np.y;
#endif

    // ── Plastique du boîtier ────────────────────────────────────
    vec3 plastic = CASE_COLOR;
#if USE_BORDER_COLOR
    if (borderColor.a > 0.0)
        plastic = borderColor.rgb;
#endif
    vec3 fcol = plastic + vec3(0.03) * (1.0 - np.y);   // léger dégradé vertical

    // Arête arrondie du boîtier : reflet côté lumière, plus large côté charnière
    vec2  nOut      = rrNormal(lp, caseCenter, caseHalf, rOut);
    float ndl       = dot(nOut, L);
    float edgeDepth = -dCase;
    float rollW     = rollBase * rim * (1.0 + 0.9 * smoothstep(0.3, 0.9, -nOut.x));
    float roll      = clamp(1.0 - edgeDepth / rollW, 0.0, 1.0);
    roll = roll * roll;
    fcol += vec3(0.55 * glossK) * pow(max(ndl, 0.0), 2.0) * roll;
    fcol *= 1.0 - 0.45 * max(-ndl, 0.0) * roll;      // côté opposé à la lumière plus sombre

    // Fine nervure moulée sur le pourtour
    float ridge = 1.0 - smoothstep(0.0, max(0.07 * rim, 1.0), abs(edgeDepth - 0.55 * rim));
    fcol += vec3(0.04 + 0.10 * max(ndl, 0.0)) * ridge;

    // Rainure de la charnière (bord gauche) : paroi gauche sombre, paroi droite éclairée
    float lx = lp.x - os;
    float gx = rim * 1.3;
    float gw = max(0.16 * rim, 1.0);
    float ym = grooveOn * smoothstep(rOut * 0.6, rOut * 1.6 + 1.0, min(lp.y - os, H - os - lp.y));
    float gDark = (1.0 - smoothstep(0.0, gw, abs(lx - gx))) * ym;
    float gLite = (1.0 - smoothstep(0.0, gw, abs(lx - gx - gw * 1.5))) * ym;
    fcol = fcol * (1.0 - 0.85 * gDark) + vec3(0.22 * glossK) * gLite;

    // Rebord de la fenêtre : tranche éclairée en bas / à droite de l'ouverture
    vec2  nWin   = rrNormal(lp, winCenter, winHalf, rIn);
    float ndlLip = dot(-nWin, L);
    float lipW   = max(0.22 * rim, 1.0);
    float lip    = 1.0 - smoothstep(0.0, lipW + aa, max(dWin, 0.0));
    fcol += vec3(0.28 * glossK) * lip * max(ndlLip, 0.0);

    // Reflet diagonal doux sur le plastique + grain
    float sh  = np.x * 0.85 + np.y * 0.65;
    float u1  = (sh - 0.55) / 0.14;
    fcol += vec3(0.06 * glossK) * exp(-u1 * u1);
    fcol += (hash21(floor(lp)) - 0.5) * 0.014;

    // Bande de dos (slim) : à gauche, entre le haut et le bas du cadre, on ne voit pas
    // de cadre coloré mais la tranche claire du boîtier ; le cadre haut/bas s'arrête en arrondi.
    if (spineOn > 0.5) {
        float yIn = smoothstep(winMin.y - aa, winMin.y + aa, lp.y)
                  * (1.0 - smoothstep(winMax.y - aa, winMax.y + aa, lp.y));
        float xIn = 1.0 - smoothstep(winCenter.x - 1.0, winCenter.x, lp.x);
        float lxn = clamp((lp.x - os) / max(hinge, 1.0), 0.0, 1.0);
        vec3 spine = mix(vec3(0.28), vec3(0.58, 0.60, 0.62), smoothstep(0.0, 0.35, lxn))
                   * mix(1.0, 0.82, lxn);
        fcol = mix(fcol, spine, yIn * xIn);
    }
    fcol = max(fcol, 0.0);

    // ── Pochette (image) derrière le film plastique ─────────────
    vec3 art = sampledColor.rgb;

    // Ombre du rebord sur l'image, plus marquée en haut / à gauche
    float depth  = max(-dWin, 0.0);
    float k      = clamp(dot(nWin, L) * 0.5 + 0.5, 0.0, 1.0);
    float shadow = 1.0 - smoothstep(0.0, lipSh, depth);
    shadow = shadow * shadow * mix(0.3, 1.0, k);
    vec4 isc = (innerShadowColor.a > 0.0) ? innerShadowColor : vec4(0.0, 0.0, 0.0, 0.55);
    art = mix(art, isc.rgb, isc.a * shadow);

    // Reflets du film plastique transparent (large bande + fine bande)
    float u2 = (sh - 0.50) / 0.17;
    float u3 = (sh - 0.78) / 0.035;
    float gloss = (0.07 * exp(-u2 * u2) + 0.04 * exp(-u3 * u3)) * GLOSS;
    art = mix(art, vec3(1.0), gloss);

    // ── Assemblage avec antialiasing ────────────────────────────
    vec4 frameCol = vec4(fcol, 1.0) * v_col;
    vec4 artCol   = vec4(art, sampledColor.a);

    float wWin  = 1.0 - smoothstep(-aa, aa, dWin);
    float wCase = 1.0 - smoothstep(-aa, aa, dCase);

    vec4 result = mix(frameCol, artCol, wWin) * wCase;

    // Ombre portée du boîtier (légèrement décalée vers le bas / la droite)
    if (os > 0.0) {
        float dSh = sdRoundRect(lp - vec2(0.2 * os, 0.35 * os), caseCenter, caseHalf, rOut);
        float a   = clamp(1.0 - max(dSh, 0.0) / os, 0.0, 1.0);
        vec4 sc   = (outerShadowColor.a > 0.0) ? outerShadowColor : vec4(0.0, 0.0, 0.0, 0.7);
        sc *= v_col;
        sc.a *= a * a;
        result += sc * (1.0 - wCase);
    }

    FragColor = result;
}
#endif
