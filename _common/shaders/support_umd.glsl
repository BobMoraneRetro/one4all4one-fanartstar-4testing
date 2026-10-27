// support_umd.glsl : support UMD (PSP) dont seul le disque intérieur tourne, la coque reste fixe.
// Le disque = cercle de centre (u_centreX, u_centreY) (fractions de l image) et de rayon u_rayon (fraction de la largeur),
// mesuré sur les images de supports PSP (médiane : 0.50, 0.49, 0.464). u_angle (degrés) est animé par le thème (shader.u_angle).
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
precision mediump float;
#endif

uniform sampler2D u_tex;
uniform vec2  textureSize;
uniform float u_angle;
uniform float u_centreX;
uniform float u_centreY;
uniform float u_rayon;
uniform float u_rayonCentre;        // centre fixe de l UMD (moyeu « UMD »), fraction de la largeur (médiane mesurée 0.221)

COMPAT_VARYING vec2 v_tex;
COMPAT_VARYING vec4 v_col;

void main(void) {
    vec2  c   = vec2(u_centreX, u_centreY);
    float k   = (textureSize.x > 0.0) ? textureSize.y / textureSize.x : 1.0;   // hauteur / largeur de l image
    vec2  p   = (v_tex - c) * vec2(1.0, k);                                      // repère en fractions de la largeur
    float d   = length(p);
    vec4  col = COMPAT_TEXTURE(u_tex, v_tex);
    if (d < u_rayon && d > u_rayonCentre) {
        float a  = radians(u_angle);
        float ca = cos(a), sa = sin(a);
        vec2  q  = vec2(ca * p.x + sa * p.y, -sa * p.x + ca * p.y);              // lecture tournée de -angle : le disque tourne de +angle
        vec4  rot = COMPAT_TEXTURE(u_tex, c + q / vec2(1.0, k));
        // fondus sur le bord du disque et contre le centre fixe (4 % du rayon) : un léger écart de cadrage ne fait pas de cassure nette
        float w = smoothstep(u_rayonCentre, u_rayonCentre + 0.04 * u_rayon, d) * (1.0 - smoothstep(0.96 * u_rayon, u_rayon, d));
        col = mix(col, rot, w);
    }
    FragColor = col * v_col;
}
#endif
