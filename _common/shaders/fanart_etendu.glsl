// fanart_etendu.glsl : fanart nette au centre, prolongée jusqu'aux bords de l'écran par la même image agrandie, floutée et assombrie.
// À poser sur une image de la taille de l'écran (pos 0 0, size 1 1) : l'image est étirée, le shader recalcule lui-même les deux cadrages.
//   centre : image entière, hauteur = hauteur (fraction de l'écran), en haut + decalageHaut, centrée en largeur ;
//   fond   : même image agrandie pour couvrir l'écran (x fondZoom), floutée (flou, en pixels), désaturée et assombrie ;
//   transition douce de « transition » pixels à l'intérieur des bords gauche, droit et bas de l'image centrale (pas en haut).
// Coût : le flou (28 échantillons) n'est calculé que hors de l'image centrale ; au centre, une seule lecture.
// Paramètres : hauteur (0.8), decalageHaut (0), fondZoom (1.08), flou (24), assombrir (0.45), saturationFond (0.8), transition (70),
//   vignettage (0 = aucun ; assombrissement supplémentaire du fond vers les bords de l'écran).
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
// dFdy requis pour détecter le sens de la texture (GLSL ES 1.0)
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
			
COMPAT_VARYING   vec4      v_col;
COMPAT_VARYING   vec2      v_tex;
COMPAT_VARYING   vec2      v_pos;

uniform   sampler2D u_tex;
uniform   vec2      resolution;
uniform   vec2      textureSize;
uniform   vec2      outputSize;
uniform   vec2      outputOffset;

uniform   float      hauteur;
uniform   float      decalageHaut;
uniform   float      fondZoom;
uniform   float      flou;
uniform   float      assombrir;
uniform   float      saturationFond;
uniform   float      transition;
uniform   float      distanceFond;      // distance (pixels) au bord de l'image nette où l'assombrissement est complet
uniform   float      vignettage;        // assombrissement supplémentaire du fond vers les bords de l'écran (0 = aucun)

#define TAPS 28

// coordonnée « depuis le haut de l'image » -> coordonnée de texture
vec2 tc(vec2 u, bool inv) {
	return vec2(u.x, inv ? 1.0 - u.y : u.y);
}
#define GOLDEN_ANGLE 2.39996323

void main(void)
{
	vec2  S    = vec2(abs(outputSize.x), abs(outputSize.y));          // taille de l'écran (pixels)
	float A    = textureSize.x / max(textureSize.y, 1.0);              // proportions de l'image
	// position à l'écran depuis le HAUT (v_pos), et sens réel de la texture (v_tex peut partir du bas : on le détecte)
	vec2  q    = clamp((v_pos - outputOffset) / S, 0.0, 1.0);
	bool  inv  = dFdy(v_tex.y) * dFdy(v_pos.y) < 0.0;
	float h    = (hauteur > 0.0) ? hauteur : 0.8;
	float T    = (transition > 0.0) ? transition : 70.0;

	// --- image centrale nette ---
	float wc   = h * S.y * A / S.x;                                   // largeur, fraction de l'écran
	float x0   = (1.0 - wc) * 0.5;
	vec2  uvc  = vec2((q.x - x0) / wc, (q.y - decalageHaut) / h);
	float dl   = (q.x - x0) * S.x;
	float dr   = (x0 + wc - q.x) * S.x;
	float db   = (decalageHaut + h - q.y) * S.y;
	float dt   = (q.y - decalageHaut) * S.y;
	float m    = smoothstep(0.0, T, dl) * smoothstep(0.0, T, dr) * smoothstep(0.0, T, db) * step(0.0, dt);

	vec4 net = vec4(0.0);
	if (m > 0.0)
		net = COMPAT_TEXTURE(u_tex, tc(clamp(uvc, 0.0, 1.0), inv));

	vec4 col = net;
	if (m < 0.999) {
		// --- fond : image agrandie qui couvre l'écran, floutée ---
		float z  = (fondZoom > 0.0) ? fondZoom : 1.08;
		float Sa = S.x / S.y;
		vec2  bf = (A > Sa) ? vec2(A / Sa, 1.0) * z : vec2(1.0, Sa / A) * z;   // taille du fond, fraction de l'écran
		vec2  uvb = (q - (1.0 - bf) * 0.5) / bf;
		float r  = (flou > 0.0) ? flou : 24.0;
		vec2  px = 1.0 / (bf * S);                                       // 1 pixel d'écran en coordonnées du fond
		vec4  acc = COMPAT_TEXTURE(u_tex, tc(clamp(uvb, 0.0, 1.0), inv));
		float ws  = 1.0;
		// flou : TAPS points en spirale régulière (plus denses au centre, poids gaussien) ; assez de points pour que les copies
		// se fondent (pas de dédoublement) sans rotation par pixel (qui faisait du grain)
		for (int i = 0; i < TAPS; i++) {
			float fi = float(i) + 0.5;
			float d  = sqrt(fi / float(TAPS));
			float a  = fi * GOLDEN_ANGLE;
			float w  = exp(-2.0 * d * d);
			acc += COMPAT_TEXTURE(u_tex, tc(clamp(uvb + vec2(cos(a), sin(a)) * d * r * px, 0.0, 1.0), inv)) * w;
			ws  += w;
		}
		vec4 fond = acc / ws;
		// assombrissement et désaturation PROGRESSIFS : nuls au raccord avec l'image nette, complets à « distanceFond » pixels
		// de son bord (pas de marche visible sur une fanart claire)
		float dOut = max(max(-dl, -dr), -db);
		float pg   = smoothstep(0.0, (distanceFond > 0.0) ? distanceFond : 350.0, dOut);
		vec3 gris = vec3(dot(fond.rgb, vec3(0.34, 0.55, 0.11)));
		float sat = mix(1.0, (saturationFond > 0.0) ? saturationFond : 0.8, pg);
		fond.rgb  = mix(gris, fond.rgb, sat) * (1.0 - clamp(assombrir, 0.0, 1.0) * pg);
		// vignettage : le fond s'assombrit encore en allant vers les bords de l'écran (le regard revient au centre)
		float ev  = smoothstep(0.3, 0.85, length((q - vec2(0.5, 0.4)) * vec2(1.25, 1.0)));
		fond.rgb *= 1.0 - clamp(vignettage, 0.0, 1.0) * ev;
		fond.a    = 1.0;
		col = mix(fond, net, m);
	}
	FragColor = vec4(col.rgb, 1.0) * v_col;
}
#endif
