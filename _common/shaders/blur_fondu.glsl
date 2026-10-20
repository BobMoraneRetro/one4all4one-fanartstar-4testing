// blur_fondu.glsl - flou d'écran (screenshader) à bord progressif
// Le flou est maximal sur le bord extérieur choisi et diminue jusqu'à zéro vers l'intérieur :
// pas de cassure nette au bord de la zone, un seul screenshader remplace plusieurs flous empilés.
//
// Paramètres XML (dans <screenshader>) :
//   <blur>        rayon maximal du flou en pixels d'écran (défaut 16 ; 1080p : 12 à 24 conseillé)
//   <fadeFrom>    côté où le flou est maximal : 0 gauche, 1 droite, 2 bas, 3 haut, 4 uniforme (pas de fondu)
//   <fadeStart>   distance au bord extérieur de l ÉCRAN (0 à 1, fraction de l écran, PAS de la zone) gardée au flou maximal (défaut 0)
//   <fadeSize>    distance au bord extérieur de l ÉCRAN (0 à 1) où le flou atteint zéro (le mettre <= largeur de la zone, sinon cassure)
//                 => flou max de 0 à fadeStart, décroissance de fadeStart à fadeSize, net au-delà
//   <darken>      assombrissement ajouté au bord extérieur (0 à 1, défaut 0)
//   <darkenColor> couleur de l'assombrissement (défaut noir)
// Exemple :
//   <screenshader name="fonduleft" extra="true">
//     <path>${themePath}/_common/shaders/blur_fondu.glsl</path>
//     <pos>0 0</pos> <size>0.15 1</size>
//     <blur>18</blur> <fadeFrom>0</fadeFrom> <fadeStart>0.5</fadeStart> <fadeSize>1</fadeSize> <darken>0.3</darken>
//   </screenshader>

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

void main(void)
{
	gl_Position = MVPMatrix * vec4(VertexCoord.xy, 0.0, 1.0);
	v_tex       = TexCoord;
	v_col       = COLOR;
}

#elif defined(FRAGMENT)

// dFdx / dFdy requis pour détecter le sens de la texture capturée (GLSL ES 1.0)
#extension GL_OES_standard_derivatives : enable

#if __VERSION__ >= 130
#define COMPAT_VARYING in
#define COMPAT_TEXTURE texture
#ifdef GL_ES
out mediump vec4 FragColor;
#else
out vec4 FragColor;
#endif
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

COMPAT_VARYING vec4 v_col;
COMPAT_VARYING vec2 v_tex;

uniform sampler2D u_tex;
uniform COMPAT_PRECISION vec2  textureSize;
uniform COMPAT_PRECISION float blur;
uniform int                    fadeFrom;
uniform COMPAT_PRECISION float fadeStart;
uniform COMPAT_PRECISION float fadeSize;
uniform COMPAT_PRECISION float darken;
uniform COMPAT_PRECISION vec4  darkenColor;

// 32 échantillons répartis en spirale (disque de Vogel) : flou rond et régulier, coût fixe
#define TAPS 32
#define GOLDEN_ANGLE 2.39996323

void main(void)
{
	float radiusMax = (blur > 0.0) ? blur : 16.0;
	float fStart    = clamp(fadeStart, 0.0, 0.99);
	float fSize     = (fadeSize > 0.0) ? clamp(fadeSize, fStart + 0.01, 1.0) : 1.0;

	// Sens réel de la capture : gl_FragCoord monte vers le haut de l'écran et va vers la droite.
	// Ne pas déplacer ces dérivées dans un if (flux non uniforme).
	float dx = dFdx(v_tex.x);
	float dy = dFdy(v_tex.y);
	float fromLeft   = (dx >= 0.0) ? v_tex.x : 1.0 - v_tex.x;   // 0 au bord gauche de l'écran
	float fromBottom = (dy >= 0.0) ? v_tex.y : 1.0 - v_tex.y;   // 0 au bord bas de l'écran

	// distance au bord extérieur (0 = bord où le flou est maximal)
	float s = 0.0;
	if      (fadeFrom == 1) s = 1.0 - fromLeft;
	else if (fadeFrom == 2) s = fromBottom;
	else if (fadeFrom == 3) s = 1.0 - fromBottom;
	else                    s = fromLeft;

	// k = 1 de 0 à fadeStart, décroît jusqu'à 0 en fadeSize ; 4 = flou uniforme
	float k = (fadeFrom == 4) ? 1.0 : 1.0 - smoothstep(fStart, fSize, s);

	vec2 texel  = 1.0 / textureSize;
	float r     = radiusMax * k;

	vec4  acc  = COMPAT_TEXTURE(u_tex, v_tex);
	float wsum = 1.0;
	for (int i = 0; i < TAPS; i++)
	{
		float fi = float(i) + 0.5;
		float d  = sqrt(fi / float(TAPS));          // 0..1, répartition uniforme sur le disque
		float a  = fi * GOLDEN_ANGLE;
		float w  = exp(-2.0 * d * d);               // pondération gaussienne
		vec2  o  = vec2(cos(a), sin(a)) * (d * r) * texel;
		acc  += COMPAT_TEXTURE(u_tex, v_tex + o) * w;
		wsum += w;
	}
	vec4 col = acc / wsum;

	// assombrissement progressif vers le bord extérieur
	vec3 dCol = (darkenColor.a > 0.0) ? darkenColor.rgb : vec3(0.0);
	col.rgb   = mix(col.rgb, dCol, clamp(darken, 0.0, 1.0) * k);

	FragColor = vec4(col.rgb, 1.0) * v_col;
}
#endif
