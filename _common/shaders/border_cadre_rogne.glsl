// border_cadre_rogne.glsl : border_cadre.glsl qui RECADRE l image sur sa partie visible avant de dessiner le cadre.
// Pour les captures livrées avec des bandes transparentes (ex. écran Game Gear dans une image 640x480) : le cadre
// entoure l écran du jeu et non toute l image. Bandes détectées par recherche dichotomique de l alpha sur la ligne
// et la colonne centrales (une vingtaine de lectures). u_alignX / u_alignY : où placer la zone recadrée dans
// l élément (0 = gauche / haut, 0.5 = centre, 1 = droite / bas) ; même alignement que la vidéo qui la remplace.
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

uniform   float      borderSize;
uniform   vec4       borderColor;
uniform   float      cornerRadius;
uniform   float      innerShadowSize;
uniform   vec4       innerShadowColor;

uniform   float      outerShadowSize;
uniform   vec4       outerShadowColor;

uniform   float		saturation;

uniform bool		bilinearFiltering;

uniform   float     u_alignX;
uniform   float     u_alignY;

vec4 sampleTexture(sampler2D tex, vec2 texCoord) 
{
    // Check if the texture coordinate is within the [0, 1] range
   // if (texCoord.x >= 0 && texCoord.x <= 1 && texCoord.y >= 0 && texCoord.y <= 1)
        return COMPAT_TEXTURE(tex, texCoord);
    
  //  return vec4(0.0); // Return transparent black for coordinates outside [0, 1]    
}

float getComputedValue(float value, float defaultValue) {
	if (value == 0.0)
		return defaultValue;
	
	if (value < 1.0)
		return abs(outputSize.y) * value;
	
	return value;
}

float opaque(vec2 uv)
{
	return step(0.5, COMPAT_TEXTURE(u_tex, uv).a);
}

// premier point opaque en partant du bord (0 -> 0.5) ou du bord opposé (1 -> 0.5), le long de la ligne centrale (axe x) ou de la colonne centrale (axe y)
float bordOpaque(bool axeX, bool depuisDebut)
{
	vec2 bord = axeX ? vec2(depuisDebut ? 0.002 : 0.998, 0.5) : vec2(0.5, depuisDebut ? 0.002 : 0.998);
	if (opaque(bord) > 0.5)
		return depuisDebut ? 0.0 : 1.0;
	float lo = depuisDebut ? 0.0 : 0.5;
	float hi = depuisDebut ? 0.5 : 1.0;
	for (int i = 0; i < 10; i++) {
		float mid = 0.5 * (lo + hi);
		float o = opaque(axeX ? vec2(mid, 0.5) : vec2(0.5, mid));
		if (depuisDebut) { if (o > 0.5) hi = mid; else lo = mid; }
		else             { if (o > 0.5) lo = mid; else hi = mid; }
	}
	return depuisDebut ? hi : lo;
}

void main(void)
{
	// ── zone visible de l image (en coordonnées de texture), sinon image entière ──
	vec2 A = vec2(0.0), B = vec2(1.0);
	if (opaque(vec2(0.5)) > 0.5) {
		A = vec2(bordOpaque(true, true), bordOpaque(false, true));
		B = vec2(bordOpaque(true, false), bordOpaque(false, false));
		if (B.x - A.x < 0.2 || B.y - A.y < 0.2) { A = vec2(0.0); B = vec2(1.0); }
	}
	vec2 ext  = B - A;
	vec2 full = abs(outputSize);
	vec2 sz   = full * ext;                                   // taille de la zone recadrée (pixels)
	vec2 off  = (full - sz) * vec2(u_alignX, u_alignY);       // position de la zone dans l élément
	vec2 lp   = v_pos - outputOffset - off;
	if (lp.x < 0.0 || lp.y < 0.0 || lp.x > sz.x || lp.y > sz.y)
		discard;
	vec2 tz   = lp / sz;                                      // 0..1 dans la zone recadrée

	float outerBorder = getComputedValue(borderSize, 0.0);
	float innerShadow = getComputedValue(innerShadowSize, 0.0);
	float outerShadow = getComputedValue(outerShadowSize, 0.0);
	float cornerSize = getComputedValue(cornerRadius, 0.0);

	// marge du cadre (mêmes formules que border_cadre.glsl, rapportées à la zone recadrée)
	vec2 decal = vec2((outerBorder/2.0+outerShadow) / sz.x, (outerBorder/2.0+outerShadow) / sz.y);
	vec2 v_padtex = vec2(tz.x / (1.0 - 2.0 * decal.x) - decal.x, tz.y * (1.0 + 2.0 * decal.y) - decal.y);
	vec2 uvT = A + v_padtex * ext;

	vec4 sampledColor = sampleTexture(u_tex, uvT);

	if (saturation != 1.0) {
		vec3 gray = vec3(dot(sampledColor.rgb, vec3(0.34, 0.55, 0.11)));
		vec3 blend = mix(gray, sampledColor.rgb, saturation);
		sampledColor = vec4(blend, sampledColor.a);
	}

	sampledColor *= v_col;

	vec2 middle = sz / 2.0;
	vec2 center = abs(lp - middle);
	vec2 q = center - middle + cornerSize;

	float distance = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - cornerSize;
	if (distance > 0.0) {
		discard;
	}
	else if (distance > -(outerBorder + innerShadow + outerShadow)) {
		if (outerShadow != 0.0 && distance > -outerShadow) {
			sampledColor = outerShadowColor;
			sampledColor.a = outerShadowColor.a * (1.0 - (outerShadow + distance) / (outerShadow)) * v_col.a;
		}
		else if (distance > -(outerBorder + outerShadow)) {
			sampledColor = borderColor;
			sampledColor.a *= v_col.a;
		}
		else if (innerShadow != 0.0) {
			float val = abs(outerBorder + outerShadow + distance) / innerShadow;
			sampledColor = mix(sampledColor, innerShadowColor, innerShadowColor.a * (1.0 - val));
		}
	}
	else {
		float pixelValue = 1.0 - smoothstep(-0.75, 0.5, distance);
		sampledColor.a *= pixelValue;
		sampledColor.rgb *= pixelValue;
	}

	FragColor = sampledColor;
}
#endif
