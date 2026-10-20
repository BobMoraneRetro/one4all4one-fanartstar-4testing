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
//   2 = boîtier Sega Mega Drive / Master System (Europe) : cadre noir fin et régulier sur les 4 côtés,
//       coins peu arrondis, film plastique brillant, patte d'accroche en haut
//       (la patte prend ~11 % de la hauteur : la jaquette est un peu plus petite)
//   3 = même boîtier Sega, sans la patte d'accroche
//   4 = boîtier Sega avec patte, version brillante (plastique laqué + reflets marqués sur le film)
//   5 = boîtier CD « jewel case » (PS1...) : bords en plastique transparent (on voit le fond au travers),
//       dos noir opaque à gauche (~10 % de la largeur), coins presque vifs
//   6 = boîtier CD épais Mega-CD (Europe) : tout transparent (bandes noires imprimées sur la jaquette),
//       plateau noir visible sur le pourtour, deux colonnes de picots en relief sur la gauche
//  10 = boîtier Nintendo DS (Europe) : plastique transparent légèrement laiteux tout autour, bord gauche
//       fin, double ligne de la paroi, film très brillant (bande « NINTENDO DS » imprimée sur la jaquette)
//  11 = boîtier Nintendo 3DS (Europe) : plastique blanc cassé opaque, cadre ~2,5 % en haut / bas / droite,
//       quasi invisible à gauche, rainure fine ; borderColor reste prioritaire si renseigné
//  12 = boîtier PSP / UMD (Europe) : plastique transparent laiteux, pas de bord à gauche, haut ~2,4 %,
//       bords droit et bas plus épais (~4,3 % de la largeur), barre d'ouverture transparente dans le bord
//       droit ; bande « PSP » imprimée sur la jaquette
//  13 = boîtier PS3 Blu-ray (Europe) : plastique transparent laiteux, bandeau transparent en haut
//       (~11 % de la largeur, logos moulés non reproduits), bords fins ailleurs, gauche quasi nul
//  14 = hors série « vitrine » : tubes chromés fins en haut / droite / bas (reflet blanc, joints aux
//       coins droits), petit espace sombre contre l'image, dégradé blanc / gris à gauche
//       qui se fond dans l'image
//  15 = boîtier CD classique 3DO : comme le 5 mais dos noir strié (bouts droits), fine bande transparente
//       (charnière du couvercle) entre le dos et la jaquette, plateau noir visible à droite avec les deux
//       attaches du livret (tiges claires à embouts blancs)
//  16 = boîtier « FMV » : plastique fumé gris translucide, large bande gauche (bande grise claire avec
//       relief de charnière + zone fumée sombre), bords fins, coins arrondis, deux attaches translucides
//       (haut-gauche et bas-droite) ; le bandeau « FMV Games » fait partie de la jaquette
//  17 = boîtier CD Dreamcast (Europe) : comme le 5 mais dos en plastique bleu opaque, avec un panneau
//       en relief aux coins arrondis au milieu du dos (inscription « Dreamcast » non reproduite) ;
//       borderColor reste prioritaire pour la couleur du dos
//  18 = boîtier de cassette audio (jeux 8 bits) : plastique transparent fin tout autour, charnière
//       transparente à gauche (double ligne), plateau noir visible en haut et à droite
//   7 = invisible : aucun boîtier, l'image remplit la vignette, seul son bord est adouci
//       (anti-aliasing des images 2D, utile quand la vignette est tournée ou réduite).
//       outerShadowSize et cornerRadius restent utilisables (0 = aucun).
//   8 = boîte carton vue de face (SNES PAL...) : la jaquette est la boîte ; arêtes pliées, bords
//       légèrement usés/blanchis, léger brillant du pelliculage
//   9 = même boîte carton, très usée (d'après photos) : noirs délavés, voile marbré et petits points
//       blancs, bords effilochés, coins abîmés, fissures courtes et sinueuses près des bords
//       (différentes pour chaque jeu)
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

// Bruit 1D lissé (usure irrégulière des bords du carton)
float vnoise1(float x, float seed) {
    float i = floor(x), f = fract(x);
    float a = hash21(vec2(i, seed)), b = hash21(vec2(i + 1.0, seed));
    return mix(a, b, f * f * (3.0 - 2.0 * f));
}

// Bruit 2D lissé (frottements sur la face du carton)
float vnoise2(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 w = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), w.x),
               mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), w.x), w.y);
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

// Fente de la patte d'accroche : rectangle arrondi + bosse en demi-cercle vers le haut
float sdTabHole(vec2 p, vec2 c, vec2 hf, float bumpR) {
    return min(sdRoundRect(p, c, hf, hf.y),
               length(p - (c - vec2(0.0, hf.y))) - bumpR);
}

void main(void)
{
    // ── Type 7 : sans bordure, simple anti-aliasing (avant le test des coins transparents :
    //    il doit aussi s'appliquer aux images détourées, ex. boîtes PS Vita aux coins arrondis) ──
    if (caseType == 7) {
        vec2  size7 = abs(outputSize);
        vec2  lp7 = v_pos - outputOffset;
        float os7 = getComputedValue(outerShadowSize, 0.0);
        float r7  = min(getComputedValue(cornerRadius, 0.0), 0.5 * min(size7.x, size7.y));
        vec2  c7  = size7 * 0.5;
        vec2  hf7 = size7 * 0.5 - os7;
        float d7  = sdRoundRect(lp7, c7, hf7, r7);
        // taille d'un pixel écran dans le repère de l'image (gère réduction et rotation)
        float px7 = max(length(fwidth(lp7)) * 0.7071, 0.5);
        float cov = 1.0 - smoothstep(-1.5 * px7, 0.0, d7);    // fondu sur ~1,5 pixel à l'intérieur du bord

        vec2 sc  = max(vec2(1.0) - 2.0 * os7 / size7, vec2(0.02));
        vec2 uv7 = (v_tex - os7 / size7) / sc;
        vec4 col7 = sampleTexture(u_tex, uv7);
        // image très réduite (pas de mipmaps) : moyenne de 5 échantillons pour lisser détails et contour alpha
        vec2 fp = fwidth(uv7);
        if (max(fp.x * textureSize.x, fp.y * textureSize.y) > 1.5) {
            vec2 o = 0.35 * fp;
            col7 = (col7 * 2.0
                  + sampleTexture(u_tex, uv7 + vec2( o.x,  o.y)) + sampleTexture(u_tex, uv7 + vec2(-o.x,  o.y))
                  + sampleTexture(u_tex, uv7 + vec2( o.x, -o.y)) + sampleTexture(u_tex, uv7 + vec2(-o.x, -o.y))) / 6.0;
        }
        if (saturation != 1.0) {
            vec3 gray7 = vec3(dot(col7.rgb, vec3(0.34, 0.55, 0.11)));
            col7.rgb = mix(gray7, col7.rgb, saturation);
        }
        col7 *= v_col;
        vec4 res7 = vec4(col7.rgb, col7.a * cov);

        // ombre portée posée sous l'image ; inutile là où l'image est opaque (elle la cache entièrement) :
        // on saute alors ses lectures de texture, le résultat est identique
        if (os7 > 0.0 && res7.a < 0.999) {
            float dS7 = sdRoundRect(lp7 - vec2(0.2 * os7, 0.35 * os7), c7, hf7, r7);
            float a7  = clamp(1.0 - max(dS7, 0.0) / os7, 0.0, 1.0);
            // image détourée (coins transparents, ex. boîte 3D) : l'ombre suit uniquement la forme de
            // l'image (alpha décalé et adouci), sans halo rectangulaire autour de la vignette
            bool cut7 = sampleTexture(u_tex, vec2(0.0)).a < 0.3 || sampleTexture(u_tex, vec2(1.0)).a < 0.3;
            if (cut7) {
                vec2  su = uv7 - vec2(0.2, 0.35) * os7 / size7 / sc;
                vec2  bo = 0.35 * os7 / size7 / sc;
                float sA = 0.0;
                for (int k = 0; k < 5; k++) {
                    vec2 o = (k == 0) ? vec2(0.0) : vec2((k == 1 || k == 3) ? 1.0 : -1.0, (k < 3) ? 1.0 : -1.0) * bo;
                    vec2 u = su + o;
                    float inside = step(0.0, u.x) * step(u.x, 1.0) * step(0.0, u.y) * step(u.y, 1.0);
                    sA += sampleTexture(u_tex, clamp(u, 0.0, 1.0)).a * inside;
                }
                a7 = sA / 5.0;
            } else {
                // l'ombre suit la forme de l'image (coins arrondis transparents, ex. PS Vita)
                float aImg = sampleTexture(u_tex, uv7 - vec2(0.2, 0.35) * os7 / size7 / sc).a;
                a7 *= mix(1.0, aImg, step(dS7, 0.0));
            }
            vec4  sc7 = (outerShadowColor.a > 0.0) ? outerShadowColor : vec4(0.0, 0.0, 0.0, 0.7);
            sc7 *= v_col;
            float sA7  = sc7.a * a7 * a7;
            float outA = res7.a + sA7 * (1.0 - res7.a);
            res7 = vec4((res7.rgb * res7.a + sc7.rgb * sA7 * (1.0 - res7.a)) / max(outA, 1e-4), outA);
        }
        FragColor = res7;
        return;
    }

    // Si on sort prématurément, il faut quand même appliquer v_col
    if (sampleTexture(u_tex, vec2(1.0)).a < 0.3 || sampleTexture(u_tex, vec2(0.0)).a < 0.3) {
        FragColor = sampleTexture(u_tex, v_tex) * v_col;
        return;
    }

    vec2  size    = abs(outputSize);
    float W       = size.x;
    float H       = size.y;
    float minSide = min(W, H);

    // ── Types 8 / 9 : boîte carton vue de face (9 = très usée) ──
    if (caseType == 8 || caseType == 9) {
        float wa  = (caseType == 9) ? 1.0 : 0.0;             // niveau d'usure supplémentaire
        vec2  lp8 = v_pos - outputOffset;
        float os8 = getComputedValue(outerShadowSize, 0.0);
        float px8 = max(length(fwidth(lp8)) * 0.7071, 0.5);
        float gT8 = dot(vec2(dFdx(v_tex.y), dFdy(v_tex.y)), vec2(dFdx(lp8.y), dFdy(lp8.y)));
        // face : proportions de la jaquette conservées
        float fw0 = W - 2.0 * os8;
        float fh0 = H - 2.0 * os8;
        float sI  = max(0.0, 0.5 * (fw0 - fh0 * W / H));
        float vI  = max(0.0, 0.5 * (fh0 - fw0 * H / W));
        vec2  fMin = vec2(os8 + sI, os8 + vI);
        vec2  fMax = vec2(W - os8 - sI, H - os8 - vI);
        vec2  gMax = fMax;
        vec2  gC = 0.5 * (fMin + gMax), gHf = 0.5 * (gMax - fMin);
        float r8  = min(getComputedValue(cornerRadius, mix(0.004, 0.016, wa) * minSide), 0.5 * minSide);
        float d8  = sdRoundRect(lp8, gC, gHf, r8);
        float cov = 1.0 - smoothstep(-1.5 * px8, 0.0, d8);

        if (cov <= 0.0 && os8 <= 0.0) { FragColor = vec4(0.0); return; }

        // coordonnées image calculées depuis la position (y vers le bas), puis dans le sens de la texture
        float fwid = fMax.x - fMin.x, fhgt = fMax.y - fMin.y;
        float ux   = clamp((lp8.x - fMin.x) / fwid, 0.0, 1.0);
        float uyD  = clamp((lp8.y - fMin.y) / fhgt, 0.0, 1.0);
        vec4  col8 = sampleTexture(u_tex, vec2(ux, (gT8 < 0.0) ? 1.0 - uyD : uyD));
        if (saturation != 1.0)
            col8.rgb = mix(vec3(dot(col8.rgb, vec3(0.34, 0.55, 0.11))), col8.rgb, saturation);

        vec2  L8  = normalize(vec2(-0.55, -0.85));
        float e   = -d8;                                         // distance au bord extérieur
        float u   = 0.0035 * minSide;
        vec2  n8  = rrNormal(lp8, gC, gHf, r8);
        float lit = dot(n8, L8);

        // Face : arête éclairée côté lumière, pli sombre juste à l'intérieur du bord
        vec3  c   = col8.rgb;
        vec3  paper = vec3(0.93, 0.92, 0.88);                    // carton mis à nu
        if (wa > 0.0) {                                          // couleurs passées : noirs délavés, un peu ternies
            vec3 faded = mix(vec3(dot(c, vec3(0.30, 0.59, 0.11))), c, 0.85) * 0.86 + vec3(0.075, 0.075, 0.08);
            c = mix(c, faded, wa);
            paper = vec3(0.80, 0.80, 0.78);                      // carton nu grisâtre
        }
        float bev = 1.0 - smoothstep(0.0, max(1.2 * u, 1.3 * px8), e);
        c = mix(c, c + 0.25 * max(lit, 0.0), bev * 0.8);
        c *= 1.0 - 0.35 * bev * max(-lit, 0.0);
        float fold = 1.0 - smoothstep(0.0, max(0.5 * u, 1.3 * px8), abs(e - 2.2 * u));
        c *= 1.0 - 0.18 * fold;
        float fr   = 1.0 - smoothstep(0.0, max(0.5 * u, 1.3 * px8), abs(lp8.x - (fMax.x - 3.5 * u)));
        c *= 1.0 - 0.12 * fr;
        // reflet du pelliculage (face seulement)
        vec2  np8 = lp8 / size;
        float ug8 = (np8.x * 0.85 + np8.y * 0.65 - 0.55) / 0.20;
        c = mix(c, vec3(1.0), 0.05 * GLOSS * exp(-ug8 * ug8));

        // Très usée : voile marbré, petits points blancs, fissures courtes et sinueuses près des bords
        // (graine tirée de l'image : chaque jeu a ses propres fissures)
        if (wa > 0.0) {
            vec3  sdc  = sampleTexture(u_tex, vec2(0.37, 0.61)).rgb + sampleTexture(u_tex, vec2(0.71, 0.23)).rgb;
            float seed = fract(dot(sdc, vec3(12.9898, 78.233, 37.719)) + 0.137);
            // voile du pelliculage usé (taches douces et larges)
            float mot  = vnoise2(lp8 / (0.10 * minSide) + seed * 13.0) * 0.65
                       + vnoise2(lp8 / (0.035 * minSide) + seed * 7.0) * 0.35;
            c += vec3(0.07) * smoothstep(0.45, 0.85, mot);
            // petits points et éclats blancs (jamais plus petits qu'un pixel et demi)
            float cell = max(0.0045 * minSide, 1.5 * px8);
            float spk  = hash21(floor(lp8 / cell) + seed * 91.0);
            // rares au centre, plus nombreux près des bords
            float nearE = 1.0 - smoothstep(0.0, 0.15 * minSide, -d8);
            c = mix(c, paper, 0.35 * step(0.996 - 0.012 * nearE, spk));
            // fissures : segments courts, ondulés et interrompus, placés près des bords
            float wl = max(0.0013 * minSide, 1.1 * px8);
            for (int k = 0; k < 6; k++) {
                float fk  = float(k);
                float h1  = hash21(vec2(seed, fk));
                float h2  = hash21(vec2(seed, fk + 10.0));
                float h3  = hash21(vec2(seed, fk + 20.0));
                // point de départ près d'un des quatre bords
                float sideK = floor(h1 * 4.0);
                vec2  rel = vec2(h2, 0.04 + 0.16 * h3);
                if (sideK == 1.0) rel = vec2(h2, 1.0 - 0.04 - 0.16 * h3);
                if (sideK == 2.0) rel = vec2(0.03 + 0.12 * h3, h2);
                if (sideK == 3.0) rel = vec2(1.0 - 0.03 - 0.12 * h3, h2);
                vec2  p0  = fMin + (fMax - fMin) * rel;
                // orientation : plutôt perpendiculaire au bord, avec de la variation
                float ang = (sideK < 2.0 ? 1.5708 : 0.0) + (hash21(vec2(seed, fk + 30.0)) - 0.5) * 1.4;
                vec2  nk  = vec2(cos(ang), sin(ang));
                float hl  = (0.04 + 0.08 * hash21(vec2(seed, fk + 40.0))) * minSide;   // demi-longueur
                float tl  = dot(lp8 - p0, vec2(-nk.y, nk.x));
                float dl  = dot(lp8 - p0, nk)
                          + (vnoise1(tl / (0.025 * minSide), seed * 40.0 + fk) - 0.5) * 0.020 * minSide
                          + (vnoise1(tl / (0.006 * minSide), seed * 60.0 + fk) - 0.5) * 0.005 * minSide;
                float ends  = 1.0 - smoothstep(0.5 * hl, hl, abs(tl));
                float brk   = smoothstep(0.25, 0.5, vnoise1(tl / (0.010 * minSide), seed * 50.0 + fk));
                float crack = (1.0 - smoothstep(0.0, wl, abs(dl))) * brk * ends;
                c = mix(c, paper, 0.55 * crack * wa);
                c *= 1.0 - 0.10 * (1.0 - smoothstep(0.0, 2.5 * wl, abs(dl - 1.5 * wl))) * ends * wa;
            }
        }

        // Usure : bords blanchis par endroits, plus marquée dans les coins et en bas
        float along = (abs(n8.x) > abs(n8.y)) ? lp8.y : lp8.x;
        float side  = (abs(n8.x) > abs(n8.y)) ? sign(n8.x) : 2.0 + sign(n8.y);
        float nz    = vnoise1(along / (0.02 * minSide), side) * 0.7 + vnoise1(along / (0.006 * minSide), side + 7.0) * 0.3;
        vec2  dc    = min(lp8 - fMin, gMax - lp8);
        float corner = 1.0 - smoothstep(0.0, 0.05 * minSide, length(dc));
        float bottom = smoothstep(0.0, 0.9, n8.y);
        float ww    = u * (0.5 + 2.6 * smoothstep(0.55, 0.95, nz) + 3.6 * corner + 1.0 * bottom) * (1.0 + 1.8 * wa);
        float wear  = (1.0 - smoothstep(0.0, max(ww, px8), e)) * (mix(0.35, 0.6, wa) + 0.65 * smoothstep(0.4, 0.8, nz));
        c = mix(c, paper, clamp(wear * mix(0.85, 1.0, wa), 0.0, 1.0));
        if (wa > 0.0) {                                          // coins abîmés, contour irrégulier
            float nzc   = vnoise1(atan(dc.y, dc.x) * 5.0, side + 3.0);
            float crush = 1.0 - smoothstep(0.0, max(0.020 * minSide * (0.5 + nzc), px8), length(dc));
            c = mix(c, paper, 0.7 * crush * wa);
        }
        c += (hash21(floor(lp8)) - 0.5) * 0.012;                  // grain du carton

        vec4 res8 = vec4(max(c, 0.0), col8.a) * v_col;
        res8.a *= cov;
        if (os8 > 0.0) {                                         // ombre portée
            float dS8 = sdRoundRect(lp8 - vec2(0.2 * os8, 0.35 * os8), gC, gHf, r8);
            float a8  = clamp(1.0 - max(dS8, 0.0) / os8, 0.0, 1.0);
            vec4  sc8 = (outerShadowColor.a > 0.0) ? outerShadowColor : vec4(0.0, 0.0, 0.0, 0.7);
            sc8 *= v_col;
            float sA8  = sc8.a * a8 * a8;
            float outA = res8.a + sA8 * (1.0 - res8.a);
            res8 = vec4((res8.rgb * res8.a + sc8.rgb * sA8 * (1.0 - res8.a)) / max(outA, 1e-4), outA);
        }
        FragColor = res8;
        return;
    }


    // ── Dimensions du boîtier (en pixels) ──────────────────────
    // Paramètres propres à chaque forme de boîtier (ajouter un `else if` pour une nouvelle forme)
    float rimAuto, hingeK, radK, rInK, rollBase, glossK, grooveOn, spineOn, lipK;
    float grainK = 0.014, sleeveK = 1.0, tabOn = 0.0, glareOn = 0.0, keepAspect = 0.0, clearOn = 0.0;
    float spineOpaque = 1.0, trayOn = 0.0, dotsOn = 0.0, milkA = 0.30;
    vec3  caseBase = CASE_COLOR;                    // couleur du plastique si borderColor absent
    float rightK = 1.0, bottomK = 1.0, topK = 1.0;  // épaisseur des bords droit / bas / haut (× rim)
    float latchOn = 0.0;                            // barre d'ouverture transparente dans le bord droit (PSP)
    vec3  clearTint = vec3(0.88, 0.90, 0.93);       // teinte du plastique transparent
    float chromeOn = 0.0;                           // liseré chromé extérieur + trait sombre intérieur (hors série)
    float ribOn = 0.0, tabsOn = 0.0, spineGap = 0.0; // 3DO : dos strié, attaches du livret, espace dos / jaquette (× rim)
    float fmvOn = 0.0;
    float dcPanel = 0.0;                            // Dreamcast : panneau en relief sur le dos
    float k7On = 0.0;                               // cassette : plateau noir en haut et à droite                              // boîtier FMV : bande gauche claire + fumée, attaches translucides
    if (caseType == 1) {            // slim console : cadre sur 3 côtés, simple bande de dos à gauche
        rimAuto = 0.026; hingeK = 0.16; radK = 1.2; rInK = 0.3;
        rollBase = 0.55; glossK = GLOSS * 1.3; grooveOn = 0.0;
        spineOn = 1.0;   lipK = 0.3;
    } else if (caseType >= 2 && caseType <= 4) {   // Sega Mega Drive / Master System : cadre fin, film brillant
        rimAuto = 0.016; hingeK = 1.0; radK = 0.6; rInK = 0.15;
        rollBase = 0.60; glossK = GLOSS * 1.1; grooveOn = 0.0;
        spineOn = 0.0;   lipK = 0.8;
        grainK = 0.02;   sleeveK = 1.8;
        tabOn = (caseType == 3) ? 0.0 : 1.0;
        keepAspect = 1.0;
        if (caseType == 4) {                        // version brillante
            glossK = GLOSS * 1.9; sleeveK = 2.6; grainK = 0.008; glareOn = 1.0;
        }
    } else if (caseType == 5) {     // CD jewel case : bords transparents, dos noir à gauche
        rimAuto = 0.026; hingeK = 4.0; radK = 0.25; rInK = 0.05;
        rollBase = 0.50; glossK = GLOSS;       grooveOn = 0.0;
        spineOn = 0.0;   lipK = 0.25;
        grainK = 0.01;   sleeveK = 1.6;
        keepAspect = 1.0; clearOn = 1.0;
        spineGap = 0.5;                             // charnière transparente entre le dos et la jaquette
    } else if (caseType == 17) {    // Dreamcast EU : CD, dos bleu opaque avec panneau en relief
        rimAuto = 0.026; hingeK = 4.0; radK = 0.25; rInK = 0.05;
        rollBase = 0.50; glossK = GLOSS;       grooveOn = 0.0;
        spineOn = 0.0;   lipK = 0.25;
        grainK = 0.01;   sleeveK = 1.6;
        keepAspect = 1.0; clearOn = 1.0;
        spineGap = 0.5;
        caseBase = vec3(0.16, 0.30, 0.58);          // bleu Dreamcast (photos)
        dcPanel = 1.0;
    } else if (caseType == 18) {    // cassette audio : transparent fin, charnière à gauche, plateau noir haut / droite
        rimAuto = 0.016; hingeK = 1.8; radK = 0.4; rInK = 0.05;
        rollBase = 0.50; glossK = GLOSS;       grooveOn = 0.0;
        spineOn = 0.0;   lipK = 0.25;
        grainK = 0.0;    sleeveK = 1.8;
        keepAspect = 1.0; clearOn = 1.0;
        spineOpaque = 0.0;
        topK = 2.2;      rightK = 2.0;    bottomK = 1.1;
        k7On = 1.0;
    } else if (caseType == 6) {     // Mega-CD Europe : CD épais transparent, plateau noir, picots
        rimAuto = 0.020; hingeK = 1.3; radK = 0.25; rInK = 0.05;
        rollBase = 0.50; glossK = GLOSS;       grooveOn = 0.0;
        spineOn = 0.0;   lipK = 0.25;
        grainK = 0.01;   sleeveK = 1.6;
        keepAspect = 1.0; clearOn = 1.0;
        spineOpaque = 0.0; trayOn = 1.0; dotsOn = 1.0;
    } else if (caseType == 10) {    // Nintendo DS : transparent laiteux, bord gauche fin
        rimAuto = 0.022; hingeK = 0.6; radK = 0.5; rInK = 0.1;
        rollBase = 0.50; glossK = GLOSS;       grooveOn = 0.0;
        spineOn = 0.0;   lipK = 0.20;
        grainK = 0.008;  sleeveK = 2.2;
        keepAspect = 1.0; clearOn = 1.0;
        spineOpaque = 0.0; milkA = 0.40;
    } else if (caseType == 11) {    // Nintendo 3DS : plastique blanc opaque, bord gauche quasi nul
        rimAuto = 0.026; hingeK = 0.2; radK = 0.8; rInK = 0.1;
        rollBase = 0.55; glossK = GLOSS * 0.8; grooveOn = 0.0;
        spineOn = 0.0;   lipK = 0.35;
        grainK = 0.008;  sleeveK = 1.8;
        keepAspect = 1.0;
        caseBase = vec3(0.88, 0.88, 0.86);
    } else if (caseType == 12) {    // PSP : transparent laiteux, droite et bas plus épais
        rimAuto = 0.024; hingeK = 0.0;  radK = 0.6; rInK = 0.1;   // pas de bord à gauche
        rollBase = 0.50; glossK = GLOSS;       grooveOn = 0.0;
        spineOn = 0.0;   lipK = 0.20;
        grainK = 0.008;  sleeveK = 2.0;
        keepAspect = 1.0; clearOn = 1.0;
        spineOpaque = 0.0; milkA = 0.72;
        clearTint = vec3(0.93, 0.94, 0.95);         // blanc très laiteux
        rightK = 1.8;    bottomK = 1.8;
        latchOn = 1.0;
    } else if (caseType == 13) {    // PS3 : transparent laiteux, large bandeau en haut
        rimAuto = 0.028; hingeK = 0.35; radK = 1.4; rInK = 0.1;
        rollBase = 0.50; glossK = GLOSS;       grooveOn = 0.0;
        spineOn = 0.0;   lipK = 0.20;
        grainK = 0.008;  sleeveK = 2.0;
        keepAspect = 1.0; clearOn = 1.0;
        spineOpaque = 0.0; milkA = 0.74;
        clearTint = vec3(0.94, 0.95, 0.96);         // blanc très laiteux
        rightK = 1.0;    bottomK = 1.3;    topK = 3.9;
    } else if (caseType == 14) {    // hors série « vitrine » : cadre très fin, liseré clair, bande gauche
        rimAuto = 0.022; hingeK = 0.0;  radK = 0.9; rInK = 0.0;   // l'image va jusqu'au bord gauche
        rollBase = 0.50; glossK = GLOSS * 1.2; grooveOn = 0.0;
        spineOn = 0.0;   lipK = 0.12;
        grainK = 0.0;    sleeveK = 1.4;
        keepAspect = 1.0; clearOn = 1.0;
        spineOpaque = 0.0; milkA = 0.18;
        clearTint = vec3(0.90, 0.91, 0.93);
        chromeOn = 1.0;
    } else if (caseType == 15) {    // 3DO : CD classique, dos noir strié, attaches du livret
        rimAuto = 0.026; hingeK = 5.4; radK = 0.25; rInK = 0.05;
        rollBase = 0.50; glossK = GLOSS;       grooveOn = 0.0;
        spineOn = 0.0;   lipK = 0.25;
        grainK = 0.01;   sleeveK = 1.6;
        keepAspect = 1.0; clearOn = 1.0;
        ribOn = 1.0;     tabsOn = 1.0;     spineGap = 0.65;
        rightK = 1.85;                              // bord droit : plateau noir + bord transparent fin
        caseBase = vec3(0.13, 0.11, 0.10);          // noir brunâtre du dos (photo)
    } else if (caseType == 16) {    // FMV : plastique fumé gris, large bande gauche
        rimAuto = 0.020; hingeK = 5.6; radK = 1.5; rInK = 0.05;   // bords haut/bas fins, zone gauche ~11 %
        rollBase = 0.50; glossK = GLOSS;       grooveOn = 0.0;
        spineOn = 0.0;   lipK = 0.20;
        grainK = 0.0;    sleeveK = 1.4;
        keepAspect = 1.0; clearOn = 1.0;
        spineOpaque = 0.0; milkA = 0.50;
        clearTint = vec3(0.60, 0.60, 0.61);
        rightK = 1.33;   bottomK = 1.3;              // bord droit inchangé (~2,7 %)
        fmvOn = 1.0;
    } else {                        // 0 : DVD
        rimAuto = 0.022; hingeK = 2.4; radK = 0.8; rInK = 0.1;
        rollBase = 0.45; glossK = GLOSS;       grooveOn = 1.0;
        spineOn = 0.0;   lipK = 0.6;
        keepAspect = 1.0;
    }

    float os    = getComputedValue(outerShadowSize, 0.0);
    float rim   = min(getComputedValue(borderSize, rimAuto * minSide), 0.15 * minSide);
    float hinge = rim * hingeK;                    // côté charnière (gauche)
    float rOut  = min(getComputedValue(cornerRadius, radK * rim), 0.5 * minSide);
    float rIn   = rInK * rim;                      // coins de la fenêtre
    float lipSh = getComputedValue(innerShadowSize, lipK * rim);
    float rimR  = rim * rightK;                    // bord droit
    float rimB  = rim * bottomK;                   // bord bas
    float rimT  = rim * topK;                      // bord haut
    float tabH  = tabOn * 0.11 * H;                // hauteur de la patte d'accroche (au-dessus du boîtier)

    // Proportions de la jaquette conservées : la fenêtre garde le rapport largeur/hauteur de l'image.
    // Le boîtier est rétréci en largeur (sideIn) ou en hauteur (vIn) selon le cas, avec des bandes
    // transparentes, au lieu d'écraser l'image.
    float sideIn = 0.0, vIn = 0.0;
    if (keepAspect > 0.5) {
        float winHgt = H - 2.0 * os - tabH - rimT - rimB;
        float winWid = W - 2.0 * os - hinge - rimR;
        sideIn = max(0.0, 0.5 * (winWid - winHgt * W / H));
        vIn    = max(0.0, 0.5 * (winHgt - winWid * H / W));
    }
    float topY = os + vIn;                         // haut de l'ensemble (patte comprise)

    // ── Rétrécissement de l'image : elle remplit la "fenêtre" du boîtier ──
    vec2 decal = vec2((os + sideIn + hinge) / W, (topY + tabH + rimT) / H); // gauche, haut
    float decalR = (os + sideIn + rimR) / W;                                // droite
    float decalB = (os + vIn + rimB) / H;                                   // bas
    decal  = min(decal,  vec2(0.45));
    decalR = min(decalR, 0.45);
    decalB = min(decalB, 0.45);

    float denomX = max(1.0 - decal.x - decalR, 0.02);
    float denomY = max(1.0 - decal.y - decalB, 0.02);

    vec2 lp = v_pos - outputOffset;                // position en pixels dans la sortie (y vers le bas)

    // Sens de l'axe vertical de la texture : selon le moteur, v_tex.y peut croître vers le bas
    // (comme lp.y) ou vers le haut. Indispensable dès que les marges haut et bas diffèrent (patte).
    // Comparaison des gradients écran : insensible à une éventuelle rotation de l'image.
    float gTex = dot(vec2(dFdx(v_tex.y), dFdy(v_tex.y)), vec2(dFdx(lp.y), dFdy(lp.y)));
    float decalTexTop = (gTex < 0.0) ? decalB : decal.y;   // marge côté v_tex.y = 0

    vec2 adjustedTexCoord = vec2(
        (v_tex.x - decal.x) / denomX,
        (v_tex.y - decalTexTop) / denomY
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

    vec2 caseMin    = vec2(os + sideIn, topY + tabH);
    vec2 caseMax    = vec2(W - os - sideIn, H - os - vIn);
    vec2 caseCenter = 0.5 * (caseMin + caseMax);
    vec2 caseHalf   = 0.5 * (caseMax - caseMin);
    // rayon des coins : hors série = coins gauches vifs, coins droits arrondis
    float rUse  = (chromeOn > 0.5 && lp.x < caseCenter.x) ? min(rOut, 0.12 * rim) : rOut;
    float dCase = sdRoundRect(lp, caseCenter, caseHalf, rUse);

    // Patte d'accroche : languette centrée derrière le haut du boîtier, fente à bosse centrale
    float dTab = 1e5;
    vec2  tabC = vec2(0.0), tabHf = vec2(0.0), holeC = vec2(0.0), holeHf = vec2(0.0);
    float tabR = 0.0, bumpR = 0.0;
    if (tabOn > 0.5) {
        float tabW = 0.38 * (caseMax.x - caseMin.x);        // ~38 % de la largeur du boîtier (mesuré sur photo)
        tabR  = 0.14 * tabH;
        tabC  = vec2(0.5 * W, 0.5 * (topY + caseMin.y + 3.0 * rim));
        tabHf = vec2(0.5 * tabW, 0.5 * (caseMin.y + 3.0 * rim - topY));
        holeHf = vec2(0.30 * tabW, 0.11 * tabH);
        holeC  = vec2(0.5 * W, topY + 0.60 * tabH);
        bumpR  = 0.12 * tabW;
        dTab = max(sdRoundRect(lp, tabC, tabHf, tabR), -sdTabHole(lp, holeC, holeHf, bumpR));
    }

    vec2 winMin    = vec2(caseMin.x + hinge, caseMin.y + rimT);
    vec2 winMax    = vec2(caseMax.x - rimR, caseMax.y - rimB);
    vec2 winCenter = 0.5 * (winMin + winMax);
    vec2 winHalf   = 0.5 * (winMax - winMin);
    float dWin = sdRoundRect(lp, winCenter, winHalf, rIn);

    float aa = max(fwidth(dCase), 1.0);

    if (min(dCase, dTab) > aa && os <= 0.0) {
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
    vec3 plastic = caseBase;
#if USE_BORDER_COLOR
    if (borderColor.a > 0.0)
        plastic = borderColor.rgb;
#endif
    vec3  fcol   = vec3(0.0);
    float frameA = 1.0;
    vec2  nWin   = rrNormal(lp, winCenter, winHalf, rIn);   // sert aussi à l'ombre sur l'image
    float sh     = np.x * 0.85 + np.y * 0.65;               // sert aussi aux reflets du film

    // Optimisation : le cadre n'est visible que là où la fenêtre ne recouvre pas tout (wWin < 1,
    // soit dWin > -aa). Pour les pixels de la jaquette (~85 % de la surface), on saute tout ce calcul ;
    // le résultat est identique puisque mix(frameCol, artCol, 1.0) = artCol.
    if (dWin > -aa) {
        fcol = plastic + vec3(0.03) * (1.0 - np.y);   // léger dégradé vertical

        // Arête arrondie du boîtier : reflet côté lumière, plus large côté charnière
        vec2  nOut      = rrNormal(lp, caseCenter, caseHalf, rUse);
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
        float lx = lp.x - caseMin.x;
        float gx = rim * 1.3;
        float gw = max(0.16 * rim, 1.0);
        float ym = grooveOn * smoothstep(rOut * 0.6, rOut * 1.6 + 1.0, min(lp.y - caseMin.y, caseMax.y - lp.y));
        float gDark = (1.0 - smoothstep(0.0, gw, abs(lx - gx))) * ym;
        float gLite = (1.0 - smoothstep(0.0, gw, abs(lx - gx - gw * 1.5))) * ym;
        fcol = fcol * (1.0 - 0.85 * gDark) + vec3(0.22 * glossK) * gLite;

        // Rebord de la fenêtre : tranche éclairée en bas / à droite de l'ouverture
        float ndlLip = dot(-nWin, L);
        float lipW   = max(0.22 * rim, 1.0);
        float lip    = 1.0 - smoothstep(0.0, lipW + aa, max(dWin, 0.0));
        fcol += vec3(0.28 * glossK) * lip * max(ndlLip, 0.0);

        // Reflet diagonal doux sur le plastique + grain
        float u1  = (sh - 0.55) / 0.14;
        fcol += vec3(0.06 * glossK) * exp(-u1 * u1);
        fcol += (hash21(floor(lp)) - 0.5) * grainK;

        // Bande de dos (slim) : à gauche, entre le haut et le bas du cadre, on ne voit pas
        // de cadre coloré mais la tranche claire du boîtier ; le cadre haut/bas s'arrête en arrondi.
        if (spineOn > 0.5) {
            float yIn = smoothstep(winMin.y - aa, winMin.y + aa, lp.y)
                      * (1.0 - smoothstep(winMax.y - aa, winMax.y + aa, lp.y));
            float xIn = 1.0 - smoothstep(winCenter.x - 1.0, winCenter.x, lp.x);
            float lxn = clamp((lp.x - caseMin.x) / max(hinge, 1.0), 0.0, 1.0);
            vec3 spine = mix(vec3(0.28), vec3(0.58, 0.60, 0.62), smoothstep(0.0, 0.35, lxn))
                       * mix(1.0, 0.82, lxn);
            fcol = mix(fcol, spine, yIn * xIn);
        }
        fcol = max(fcol, 0.0);

        // Boîtier CD : plastique transparent partout sauf le dos (bande noire opaque à gauche)
        if (clearOn > 0.5) {
            // Dos : rectangle aux extrémités arrondies, du bord gauche jusqu'à la jaquette
            vec2  spMin = vec2(caseMin.x + 0.25 * rim, caseMin.y + 0.45 * rim);
            vec2  spMax = vec2(winMin.x - 1.0 - spineGap * rim, caseMax.y - 0.45 * rim);
            float spR   = (ribOn > 0.5 || spineGap > 0.0) ? 0.15 * rim : 0.9 * rim;   // PS1 / 3DO : bouts droits
            float dSp   = sdRoundRect(lp, 0.5 * (spMin + spMax), 0.5 * (spMax - spMin), spR);
            float spine = (1.0 - smoothstep(-aa, aa, dSp)) * spineOpaque;

            // Bords transparents : teinte très légère + deux liserés brillants (arête du couvercle, bord du plateau)
            float lw    = max(0.07 * rim, 1.3 * aa);   // jamais plus fin qu'un pixel : évite l'aliasing
            float e1    = 1.0 - smoothstep(0.0, lw, abs(edgeDepth - 0.10 * rim));
            float e2    = 1.0 - smoothstep(0.0, lw, abs(edgeDepth - 0.60 * rim));
            float lines = max(e1, 0.6 * e2) * (0.35 + 0.40 * max(ndl, 0.0));
            vec3  clearRGB = mix(clearTint, vec3(1.0), lines);
            float clearA   = milkA + 0.45 * lines + 0.10 * exp(-u1 * u1);

            // Dos : plastique noir, reflets atténués (sur la photo il reste bien noir)
            // reflet vertical sur le bord gauche (arrondi du couvercle par-dessus le dos)
            float lx2 = (lp.x - spMin.x) / max(spMax.x - spMin.x, 1.0);
            float ug  = (lx2 - 0.12) / 0.07;
            vec3  sp  = mix(plastic, fcol, 0.4) + vec3(0.07 * glossK) * exp(-ug * ug);
            if (dcPanel > 0.5) {               // panneau en relief : un peu plus clair, arête claire à droite / en haut
                float spw = spMax.x - spMin.x, sph = spMax.y - spMin.y;
                vec2  pc  = vec2(spMin.x + 0.52 * spw, spMin.y + 0.51 * sph);
                vec2  ph  = vec2(0.36 * spw, 0.165 * sph);
                float dP  = sdRoundRect(lp, pc, ph, 0.45 * ph.x);
                float inP = 1.0 - smoothstep(-aa, aa, dP);
                float edP = 1.0 - smoothstep(0.0, 1.3 * lw, abs(dP));
                float litP = dot(rrNormal(lp, pc, ph, 0.45 * ph.x), vec2(0.8, -0.6));
                sp = mix(sp, sp * 1.18 + vec3(0.02), inP);
                sp = mix(sp, (litP > 0.0) ? sp + vec3(0.18) : sp * 0.6, 0.8 * edP);
            }
            if (ribOn > 0.5) {                 // stries verticales du dos (pas ≥ 3 px pour éviter le moiré) :
                float per = max(0.008 * W, 3.0 * aa);   // arêtes claires / rainures sombres sur le noir
                float rib = 0.5 + 0.5 * cos(6.2832 * (lp.x - spMin.x) / per);
                sp = sp * (1.0 - 0.35 * (1.0 - rib)) + vec3(0.06, 0.055, 0.05) * rib * rib;
            }
            if (spineGap > 0.0) {              // double ligne de la charnière du couvercle dans l'espace
                float gx1 = spMax.x + 0.30 * spineGap * rim;
                float gx2 = spMax.x + 0.70 * spineGap * rim;
                float hl2 = max(1.0 - smoothstep(0.0, lw, abs(lp.x - gx1)), 1.0 - smoothstep(0.0, lw, abs(lp.x - gx2)));
                float inGapY = smoothstep(caseMin.y + 0.5 * rim, caseMin.y + rim, lp.y) * (1.0 - smoothstep(caseMax.y - rim, caseMax.y - 0.5 * rim, lp.y));
                clearRGB = mix(clearRGB, vec3(1.0), 0.55 * hl2 * inGapY);
                clearA   = min(clearA + 0.35 * hl2 * inGapY, 1.0);
            }

            // Barre d'ouverture (PSP) : large bande pâle verticale au milieu du bord droit,
            // de 20 % à 80 % de la hauteur, bouts arrondis, contour doux
            if (latchOn > 0.5) {
                vec2  lc   = vec2(caseMax.x - 0.48 * rimR, 0.5 * (caseMin.y + caseMax.y));
                vec2  lh   = vec2(max(0.32 * rimR, 1.5), 0.30 * (caseMax.y - caseMin.y));
                float dL   = sdRoundRect(lp, lc, lh, lh.x);
                // remplissage pâle qui s'estompe vers les bords (bande douce, pas un trait)
                float inL  = 1.0 - smoothstep(-0.6 * lh.x, aa, dL);
                float edgL = 1.0 - smoothstep(0.0, 1.5 * lw, abs(dL));
                float litL = dot(rrNormal(lp, lc, lh, lh.x), L);
                clearRGB = mix(clearRGB, vec3(1.0), 0.7 * inL);
                clearRGB = mix(clearRGB, (litL > 0.0) ? vec3(1.0) : vec3(0.75), 0.25 * edgL);
                clearA   = min(clearA + 0.20 * inL + 0.10 * edgL, 1.0);
            }

            // Bandeau du haut (PS3) : plastique un peu plus épais, arête du clip au-dessus de la jaquette
            if (topK > 1.5) {
                float inBand = (1.0 - smoothstep(winMin.y - aa, winMin.y + aa, lp.y))
                             * smoothstep(caseMin.y + 0.5 * rim, caseMin.y + rim, lp.y);
                float clipL  = 1.0 - smoothstep(0.0, lw, abs(lp.y - (winMin.y - 0.35 * rim)));
                clearA   = min(clearA + 0.08 * inBand + 0.30 * clipL * inBand, 1.0);
                clearRGB = mix(clearRGB, vec3(1.0), 0.6 * clipL * inBand);
            }

            // Hors série : liseré chromé blanc à l'extérieur, dégradé clair sur la tranche gauche,
            // trait sombre contre l'image
            if (chromeOn > 0.5) {
                // Bord gauche : même teinte que le début du dégradé posé sur l'image (aucun trait) ;
                // la transition se fait sous l'image pour ne laisser passer aucun pixel transparent
                float onL  = 1.0 - smoothstep(winMin.x + aa, winMin.x + 2.0 * aa, lp.x);
                clearRGB = mix(clearRGB, vec3(0.93), onL);
                clearA   = mix(clearA, 0.97, onL);

                // Tubes chromés : barres droites en haut et en bas sur toute la largeur (bout gauche net,
                // même teinte jusqu'au bout), barre verticale à droite avec coins arrondis ; pas de tube à gauche
                float tw   = 0.72 * rim;                                   // largeur du tube
                float dtb  = min(lp.y - caseMin.y, caseMax.y - lp.y);
                float tdep = (lp.x > caseCenter.x) ? edgeDepth : dtb;      // distance au bord du tube
                float tt   = clamp(tdep / max(tw, 1.0), 0.0, 1.0);         // 0 = extérieur, 1 = intérieur
                // double reflet + fin liseré brillant tout au bord extérieur ;
                // largeurs jamais inférieures à ~1 pixel écran (sinon aliasing, tube de ~3 px seulement)
                float pxT  = aa / max(tw, 1.0);                             // 1 pixel en unités de tt
                float u1h  = (tt - 0.24) / max(0.12, 0.9 * pxT);
                float u2h  = (tt - 0.76) / max(0.11, 0.9 * pxT);
                float tube = 0.50 + 0.46 * exp(-u1h * u1h) + 0.36 * exp(-u2h * u2h)
                           + 0.30 * (1.0 - smoothstep(0.0, max(0.12, 1.2 * pxT), tt));
                tube += 0.08 * max(ndl, 0.0);
                float inT  = 1.0 - smoothstep(tw - aa, tw + aa, tdep);
                // pièce d'angle à droite : joint sur les barres haut / bas un peu avant le coin
                float xj   = caseMax.x - 2.2 * tw;
                float seam = 1.0 - smoothstep(0.0, max(0.16 * rim, 1.4 * aa), abs(lp.x - xj));
                float seamL = 1.0 - smoothstep(0.0, max(0.16 * rim, 1.4 * aa), abs(lp.x - xj - 2.0 * lw));
                float onH  = 1.0 - smoothstep(tw, tw + aa, dtb);
                tube = tube * (1.0 - 0.55 * seam * onH) + 0.25 * seamL * onH;
                clearRGB = mix(clearRGB, vec3(clamp(tube, 0.0, 1.0)), inT);
                clearA   = mix(clearA, 0.97, inT);

                // petit espace sombre entre les tubes et l'image, fin trait sombre contre l'image
                // (sous les barres haut / bas, l'espace sombre va jusqu'au bord gauche)
                float underH = 1.0 - smoothstep(rimT - aa, rimT, dtb);
                float gap  = smoothstep(tw - aa, tw + aa, tdep) * max(1.0 - onL, underH);
                clearRGB = mix(clearRGB, vec3(0.12, 0.12, 0.14), gap);
                clearA   = mix(clearA, 0.65, gap);
                float inn  = (1.0 - smoothstep(0.0, lw, abs(dWin - 0.5 * lw)))
                           * smoothstep(winMin.x + 0.5 * rim, winMin.x + rim, lp.x);   // pas à gauche
                clearRGB = mix(clearRGB, vec3(0.10), 0.7 * inn);
                clearA   = mix(clearA, 0.9, inn);
            }

            // 3DO : plateau noir vu à droite entre la jaquette et le bord transparent, avec les deux
            // attaches du livret (tiges claires à embouts blancs) dans cette bande noire
            if (tabsOn > 0.5) {
                float tx0 = winMax.x, tx1 = caseMax.x - 0.6 * rim;   // bord transparent extérieur fin
                float inTx = smoothstep(tx0 - 0.5 * aa, tx0 + 0.5 * aa, lp.x) * (1.0 - smoothstep(tx1 - aa, tx1 + aa, lp.x));
                float inTy = smoothstep(caseMin.y + 0.9 * rim, caseMin.y + 0.9 * rim + aa, lp.y)
                           * (1.0 - smoothstep(caseMax.y - 0.9 * rim - aa, caseMax.y - 0.9 * rim, lp.y));
                float tr = inTx * inTy;
                vec3  trc = vec3(0.07, 0.07, 0.08) + vec3(0.05) * max(ndl, 0.0);
                clearRGB = mix(clearRGB, trc, tr);
                clearA   = mix(clearA, 0.93, tr);
                float hgt = caseMax.y - caseMin.y;
                float rx  = mix(tx0, tx1, 0.40);
                float rw  = max(0.12 * rim, 0.7 * aa);
                for (int k = 0; k < 2; k++) {
                    float y0 = caseMin.y + hgt * ((k == 0) ? 0.17 : 0.56);
                    float y1 = caseMin.y + hgt * ((k == 0) ? 0.43 : 0.82);
                    vec2  rc = vec2(rx, 0.5 * (y0 + y1));
                    float dR = sdRoundRect(lp, rc, vec2(rw, 0.5 * (y1 - y0)), rw);
                    float rod = 1.0 - smoothstep(-0.5 * aa, 0.5 * aa + 0.3 * lw, dR);
                    clearRGB = mix(clearRGB, vec3(0.78), 0.65 * rod * tr);
                    // petit coude discret aux deux extrémités (à peine plus large que la tige)
                    vec2  ch = vec2(max(1.8 * rw, 0.8 * aa), max(1.2 * rw, 0.8 * aa));
                    float dC = min(sdRoundRect(lp, vec2(rx, y0 + ch.y), ch, 0.3 * ch.x),
                                   sdRoundRect(lp, vec2(rx, y1 - ch.y), ch, 0.3 * ch.x));
                    float cap = 1.0 - smoothstep(-0.5 * aa, 0.5 * aa, dC);
                    clearRGB = mix(clearRGB, vec3(0.85), 0.35 * cap * tr);
                }
            }

            // FMV (d'après l'image de référence) : la zone gauche est un seul panneau translucide dont
            // l'opacité décroît doucement vers la jaquette ; fine rainure verticale près du bord ; encoche
            // rectiligne (bord droit droit, coin haut-droit arrondi) au milieu de la hauteur, avec son
            // ombre grise qui s'estompe jusqu'à la jaquette
            if (fmvOn > 0.5) {
                float hw   = winMin.x - caseMin.x;
                float lx   = clamp((lp.x - caseMin.x) / max(hw, 1.0), 0.0, 1.0);   // 0 = bord gauche, 1 = jaquette
                float onL  = 1.0 - smoothstep(winMin.x - aa, winMin.x + aa, lp.x);
                // dégradé resserré sur la moitié gauche de la zone, puis panneau fumé léger et uniforme
                float gx   = smoothstep(0.0, 0.45, lx);
                vec3  pc   = vec3(mix(0.64, 0.80, gx));
                float pa   = mix(0.58, 0.14, gx);
                // rainure verticale à ~20 % de la zone
                float grv  = 1.0 - smoothstep(0.0, lw, abs(lp.x - (caseMin.x + 0.20 * hw)));
                pc = mix(pc, vec3(0.45), 0.5 * grv);
                // encoche en « D » : bord gauche droit, côté droit arrondi (grands rayons haut et bas),
                // de 32 % à 68 % de la hauteur, claire avec une fine arête sombre ; pas d'ombre portée
                float ch  = caseMax.y - caseMin.y;
                vec2  eMin = vec2(caseMin.x - hw, caseMin.y + 0.32 * ch);
                vec2  eMax = vec2(caseMin.x + 0.45 * hw, caseMin.y + 0.68 * ch);
                vec2  ec  = 0.5 * (eMin + eMax), eh = 0.5 * (eMax - eMin);
                float dE  = sdRoundRect(lp, ec, eh, 0.40 * hw);
                float inE = 1.0 - smoothstep(-aa, aa, dE);
                float edE = 1.0 - smoothstep(0.0, 1.2 * lw, abs(dE + 0.5 * lw));
                pc = mix(pc, vec3(0.74), inE);
                pa = mix(pa, 0.62, inE);
                pc = mix(pc, vec3(0.30), 0.6 * edE);
                pa = mix(pa, 0.55, 0.6 * edE);
                clearRGB = mix(clearRGB, pc, onL);
                clearA   = mix(clearA, pa, onL);
                // trait sombre contre la jaquette (côté gauche)
                float jl  = (1.0 - smoothstep(0.0, lw, abs(lp.x - winMin.x + 0.6 * lw))) * onL;
                clearRGB = mix(clearRGB, vec3(0.10), 0.6 * jl);
                clearA   = mix(clearA, 0.55, jl);
                // liseré blanc tout au bord extérieur, fin trait sombre juste à l'intérieur
                float ow  = 1.0 - smoothstep(0.0, lw, edgeDepth - 0.3 * lw);
                float od  = 1.0 - smoothstep(0.0, lw, abs(edgeDepth - 1.6 * lw));
                clearRGB = mix(clearRGB, vec3(0.18), 0.6 * od);
                clearA   = mix(clearA, 0.75, 0.6 * od);
                clearRGB = mix(clearRGB, vec3(1.0), 0.7 * ow);
                clearA   = mix(clearA, 0.6, ow);
            }

            // Cassette : plateau noir visible entre le bord transparent et la jaquette, en haut et à droite ;
            // charnière transparente à gauche (double ligne verticale)
            if (k7On > 0.5) {
                float tTop = smoothstep(caseMin.y + 0.85 * rim - aa, caseMin.y + 0.85 * rim + aa, lp.y)
                           * (1.0 - smoothstep(winMin.y - aa, winMin.y + aa, lp.y))
                           * smoothstep(caseMin.x + 0.6 * rim, caseMin.x + 0.6 * rim + aa, lp.x)
                           * (1.0 - smoothstep(caseMax.x - 0.85 * rim - aa, caseMax.x - 0.85 * rim + aa, lp.x));
                float tRgt = smoothstep(winMax.x - aa, winMax.x + aa, lp.x)
                           * (1.0 - smoothstep(caseMax.x - 0.85 * rim - aa, caseMax.x - 0.85 * rim + aa, lp.x))
                           * smoothstep(caseMin.y + 0.85 * rim - aa, caseMin.y + 0.85 * rim + aa, lp.y)
                           * (1.0 - smoothstep(winMax.y - aa, winMax.y + aa, lp.y));
                float tr = max(tTop, tRgt);
                clearRGB = mix(clearRGB, vec3(0.06, 0.06, 0.07) + vec3(0.06) * max(ndl, 0.0), tr);
                clearA   = mix(clearA, 0.92, tr);
                float hx1 = caseMin.x + 0.55 * hinge, hx2 = caseMin.x + 0.80 * hinge;
                float hl  = max(1.0 - smoothstep(0.0, lw, abs(lp.x - hx1)), 1.0 - smoothstep(0.0, lw, abs(lp.x - hx2)));
                float onLh = 1.0 - smoothstep(winMin.x - aa, winMin.x + aa, lp.x);
                clearRGB = mix(clearRGB, vec3(1.0), 0.5 * hl * onLh);
                clearA   = min(clearA + 0.30 * hl * onLh, 1.0);
            }

            // Plateau noir vu à travers le couvercle, entre le bord transparent et la jaquette
            float tray = trayOn * smoothstep(0.55 * rim - aa, 0.55 * rim + aa, edgeDepth);
            clearRGB = mix(clearRGB, vec3(0.10, 0.10, 0.11) + vec3(0.10) * lines, tray);
            clearA   = mix(clearA, 0.92, tray);

            fcol   = mix(clearRGB, sp, spine);
            frameA = mix(clearA, 1.0, spine);
        }
    }

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
    float gloss = (0.07 * exp(-u2 * u2) + 0.04 * exp(-u3 * u3)) * GLOSS * sleeveK;
    if (glareOn > 0.5) {
        // Reflet de fenêtre en haut du film (plus fort à gauche) + deux traits de lumière en diagonale
        float wy    = (lp.y - winMin.y) / max(winMax.y - winMin.y, 1.0);
        float wx    = (lp.x - winMin.x) / max(winMax.x - winMin.x, 1.0);
        float sheen = (1.0 - smoothstep(0.0, 0.38, wy)) * (1.0 - 0.6 * wx);
        float u4 = (sh - 0.46) / 0.030;
        float u5 = (sh - 0.54) / 0.012;
        gloss += (0.17 * sheen + 0.22 * exp(-u4 * u4) + 0.17 * exp(-u5 * u5)) * GLOSS;
    }
    art = mix(art, vec3(1.0), gloss);

    // FMV : quatre attaches translucides (carrés arrondis) qui chevauchent les bords gauche et droit
    // de la jaquette, près du haut et du bas
    if (fmvOn > 0.5) {
        float ww = winMax.x - winMin.x, wh = winMax.y - winMin.y;
        vec2  ch = vec2(0.030 * ww, 0.034 * wh);
        for (int k = 0; k < 4; k++) {
            float cx = (k == 0 || k == 2) ? winMin.x + 0.020 * ww : winMax.x - 0.020 * ww;
            float cy = (k < 2) ? winMin.y + 0.085 * wh : winMax.y - 0.115 * wh;
            float dC  = sdRoundRect(lp, vec2(cx, cy), ch, 0.45 * ch.x);
            float inC = 1.0 - smoothstep(-aa, aa, dC);
            float edC = 1.0 - smoothstep(0.0, 1.2 * aa, abs(dC));
            art = mix(art, vec3(1.0), 0.10 * inC);
            art = mix(art, vec3(0.60), 0.20 * edC);
        }
    }

    // Hors série : dégradé blanc / gris sur le bord gauche de l'image, qui se fond dans l'image
    if (chromeOn > 0.5) {
        float gwid = 0.075 * (caseMax.x - caseMin.x);
        float gl   = 1.0 - smoothstep(0.0, gwid, lp.x - winMin.x);
        art = mix(art, vec3(0.93), gl * gl * mix(0.85, 1.0, gl));   // blanc neutre, part du bord gauche
    }

    // Picots en relief du couvercle (Mega-CD) : deux colonnes décalées sur la gauche
    if (dotsOn > 0.5) {
        float cw   = caseMax.x - caseMin.x;
        float ch   = caseMax.y - caseMin.y;
        float per  = 0.048 * ch;
        float rad  = max(0.0085 * ch, 1.0);
        float yOk  = smoothstep(winMin.y + 0.4 * per, winMin.y + 0.6 * per, lp.y)
                   * (1.0 - smoothstep(winMax.y - 0.6 * per, winMax.y - 0.4 * per, lp.y));
        float dots = 0.0, dl = 0.0;
        for (int i = 0; i < 2; i++) {
            float cx  = caseMin.x + ((i == 0) ? 0.045 : 0.11) * cw;
            float yy  = lp.y - winMin.y - ((i == 0) ? 0.0 : 0.5 * per);
            vec2  q   = vec2(lp.x - cx, yy - per * (floor(yy / per) + 0.5));
            float d   = length(q);
            float m   = 1.0 - smoothstep(rad - aa, rad + aa, d);
            dots = max(dots, m);
            dl   = max(dl, m * clamp(dot(-q / max(d, 0.001), L) * 0.5 + 0.5, 0.0, 1.0));
        }
        art = mix(art, vec3(0.24) + vec3(0.12) * dl, 0.55 * dots * yOk);
    }

    // ── Assemblage avec antialiasing ────────────────────────────
    vec4 frameCol = vec4(fcol, frameA) * v_col;
    vec4 artCol   = vec4(art, sampledColor.a);

    float wWin  = 1.0 - smoothstep(-aa, aa, dWin);
    float wCase = 1.0 - smoothstep(-aa, aa, dCase);

    vec4 result = mix(frameCol, artCol, wWin) * wCase;

    // Patte d'accroche (derrière le boîtier) : plastique un peu plus sombre, tranches éclairées
    float wTab = 0.0;
    if (tabOn > 0.5) {
        wTab = 1.0 - smoothstep(-aa, aa, dTab);
        vec3 tcol = plastic * 0.85 + vec3(0.02);
        float edge = 1.0 - smoothstep(0.0, max(0.06 * tabH, 1.0), -dTab);   // pourtour (extérieur + fente)
        vec2 nT = rrNormal(lp, tabC, tabHf, tabR);
        // tranche extérieure éclairée en haut / à gauche, paroi de la fente éclairée en bas
        float litOut  = max(dot(nT, L), 0.0);
        float litHole = smoothstep(holeC.y - holeHf.y, holeC.y + holeHf.y, lp.y);
        bool  nearOuter = sdRoundRect(lp, tabC, tabHf, tabR) > dTab - 0.5;
        tcol += vec3(0.30 * glossK) * edge * (nearOuter ? litOut : litHole);
        tcol += vec3(0.03 * glossK) * (1.0 - (lp.y - topY) / max(tabH, 1.0));
        tcol += (hash21(floor(lp)) - 0.5) * grainK;
        // Ombre du boîtier sur le bas de la patte
        tcol *= 1.0 - 0.5 * (1.0 - smoothstep(0.0, 0.25 * tabH, caseMin.y - lp.y));
        result += vec4(max(tcol, 0.0), 1.0) * v_col * wTab * (1.0 - wCase);
    }
    float wAll = 1.0 - (1.0 - wCase) * (1.0 - wTab);

    // Ombre portée du boîtier (légèrement décalée vers le bas / la droite)
    if (os > 0.0) {
        float dSh = sdRoundRect(lp - vec2(0.2 * os, 0.35 * os), caseCenter, caseHalf, rUse);
        if (tabOn > 0.5) {
            vec2 ps = lp - vec2(0.2 * os, 0.35 * os);
            dSh = min(dSh, max(sdRoundRect(ps, tabC, tabHf, tabR), -sdTabHole(ps, holeC, holeHf, bumpR)));
        }
        float a   = clamp(1.0 - max(dSh, 0.0) / os, 0.0, 1.0);
        vec4 sc   = (outerShadowColor.a > 0.0) ? outerShadowColor : vec4(0.0, 0.0, 0.0, 0.7);
        sc *= v_col;
        sc.a *= a * a;
        if (clearOn > 0.5) {
            // Boîtier transparent : l'ombre passe aussi sous les bords (atténuée), puis le boîtier
            // est posé par-dessus (« over » en alpha non prémultiplié, sans assombrir le bord)
            vec4  base  = mix(frameCol, artCol, wWin);
            float caseA = base.a * wCase;
            float sA    = sc.a * mix(1.0, 0.45, wCase);
            float outA  = caseA + sA * (1.0 - caseA);
            vec3  outC  = (base.rgb * caseA + sc.rgb * sA * (1.0 - caseA)) / max(outA, 1e-4);
            result = vec4(outC, outA);
        } else {
            result += sc * (1.0 - wAll);
        }
    } else if (clearOn > 0.5) {
        vec4 base = mix(frameCol, artCol, wWin);
        result = vec4(base.rgb, base.a * wCase);
    }

    FragColor = result;
}
#endif
