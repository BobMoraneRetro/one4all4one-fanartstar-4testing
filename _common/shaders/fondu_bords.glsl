// fondu_bords.glsl : estompe les bords d une image (alpha progressif) pour qu elle se fonde dans le fond, sans bord net.
// Paramètres (fractions de l image, 0 = pas de fondu de ce côté) : fadeLeft, fadeRight, fadeTop, fadeBottom.
// Décroissance douce (smoothstep) ; l image reste intacte au centre.
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
			
COMPAT_VARYING   vec4      v_col;
COMPAT_VARYING   vec2      v_tex;
COMPAT_VARYING   vec2      v_pos;

uniform   sampler2D u_tex;
uniform   vec2      resolution;
uniform   vec2      textureSize;
uniform   vec2      outputSize;
uniform   vec2      outputOffset;

uniform   float      fadeLeft;
uniform   float      fadeRight;
uniform   float      fadeTop;
uniform   float      fadeBottom;

float bord(float d, float f) {
	return (f > 0.0) ? smoothstep(0.0, f, d) : 1.0;
}

void main(void)
{
	vec4 col = COMPAT_TEXTURE(u_tex, v_tex) * v_col;
	// sens réel de l image : on mesure depuis chaque bord avec la position du fragment dans l élément
	vec2 size = vec2(abs(outputSize.x), abs(outputSize.y));
	vec2 p    = clamp((v_pos - outputOffset) / size, 0.0, 1.0);    // 0..1, (0,0) en haut à gauche
	float a   = bord(p.x, fadeLeft) * bord(1.0 - p.x, fadeRight) * bord(p.y, fadeTop) * bord(1.0 - p.y, fadeBottom);
	FragColor = vec4(col.rgb, col.a * a);
}
#endif
