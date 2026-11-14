/**
 * The globe's shaders. One full-screen quad; the fragment shader draws the whole planet.
 *
 * Inside the region every pixel is painted from the three hex centres around it, read from the packed
 * cell texture. Noise only adds detail, so the ground always shows the terrain the server sent.
 */

export const GLOBE_VERTEX_SHADER = `
attribute vec2 aPosition;
void main() {
  gl_Position = vec4(aPosition, 0.0, 1.0);
}
`;

export const GLOBE_FRAGMENT_SHADER = `
precision highp float;

uniform vec2 uResolution;
uniform mat3 uRotation;     // view space to planet space
uniform float uRadius;      // planet radius in canvas pixels
uniform float uTime;
uniform vec3 uSun;          // planet space
uniform vec3 uSunView;      // view space
uniform float uSeed;        // 0..100, small so noise keeps its precision
uniform vec3 uHome;
uniform vec3 uEast;
uniform vec3 uNorth;
uniform float uArc;
uniform float uRegionRadius;
uniform sampler2D uCells;
uniform float uCellsSize;
uniform float uCellsOffset;
uniform sampler2D uPalette;
uniform float uTemperature; // -0.4 cold world .. 0.4 hot world
uniform float uWetness;     // -0.3 dry .. 0.3 wet
uniform float uCloudOpacity;
uniform float uCloudShadows;
uniform float uNightFloor;

const float WATER = 9.0;

float hash(vec3 p) {
  p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
  p *= 17.0;
  return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
  vec3 i = floor(x);
  vec3 f = fract(x);
  f = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(mix(hash(i), hash(i + vec3(1.0, 0.0, 0.0)), f.x),
        mix(hash(i + vec3(0.0, 1.0, 0.0)), hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
    mix(mix(hash(i + vec3(0.0, 0.0, 1.0)), hash(i + vec3(1.0, 0.0, 1.0)), f.x),
        mix(hash(i + vec3(0.0, 1.0, 1.0)), hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
    f.z);
}

float fbm(vec3 p) {
  float amplitude = 0.5;
  float sum = 0.0;
  for (int octave = 0; octave < 4; octave++) {
    sum += amplitude * noise(p);
    p = p * 2.03 + vec3(1.7);
    amplitude *= 0.5;
  }
  return sum;
}

mat3 rotateY(float angle) {
  float c = cos(angle);
  float s = sin(angle);
  return mat3(c, 0.0, -s, 0.0, 1.0, 0.0, s, 0.0, c);
}

// ---- The region, from the cell texture ---------------------------------------------------------------

vec4 cellAt(vec2 qr) {
  qr = clamp(qr, vec2(-uCellsOffset), vec2(uCellsOffset));
  return texture2D(uCells, (qr + uCellsOffset + 0.5) / uCellsSize);
}

vec3 paletteAt(float index) {
  return texture2D(uPalette, vec2((index + 0.5) / 16.0, 0.5)).rgb;
}

// The three hex centres around a point and its barycentric weights. Hex centres form a triangular
// lattice, and in axial coordinates each unit square splits into two of its triangles.
void triangleAround(vec2 qr, out vec2 a, out vec2 b, out vec2 c, out vec3 w) {
  vec2 base = floor(qr);
  vec2 f = qr - base;
  b = base + vec2(1.0, 0.0);
  c = base + vec2(0.0, 1.0);
  if (f.x + f.y < 1.0) {
    a = base;
    w = vec3(1.0 - f.x - f.y, f.x, f.y);
  } else {
    a = base + vec2(1.0, 1.0);
    w = vec3(f.x + f.y - 1.0, 1.0 - f.y, 1.0 - f.x);
  }
}

float regionHeight(vec2 qr) {
  vec2 a; vec2 b; vec2 c; vec3 w;
  triangleAround(qr, a, b, c, w);
  return dot(w, vec3(cellAt(a).g, cellAt(b).g, cellAt(c).g));
}

vec2 toAxial(vec2 flatPosition) {
  float r = flatPosition.y / 1.5;
  return vec2(flatPosition.x / 1.7320508 - r * 0.5, r);
}

float hexDistance(vec2 qr) {
  return max(max(abs(qr.x), abs(qr.y)), abs(qr.x + qr.y));
}

// Ground colour inside the region. Alpha is how much of it is hidden under fog of the unknown.
vec4 regionGround(vec3 p, vec2 qr) {
  vec2 a; vec2 b; vec2 c; vec3 w;
  triangleAround(qr, a, b, c, w);
  vec4 ca = cellAt(a);
  vec4 cb = cellAt(b);
  vec4 cc = cellAt(c);
  vec3 index = floor(vec3(ca.r, cb.r, cc.r) * 255.0 + 0.5);
  vec3 known = step(0.5, vec3(ca.a, cb.a, cc.a));
  vec3 water = known * vec3(equal(index, vec3(WATER)));
  vec3 rock = known * clamp(vec3(ca.b, cb.b, cc.b) * 3.0 - 1.4, 0.0, 1.0);

  // Sharp weights keep each hex its own colour; softer ones round the coast and the fog.
  vec3 sharp = w * w * w * w;
  sharp /= max(dot(sharp, vec3(1.0)), 0.0001);
  vec3 soft = w * w;
  soft /= max(dot(soft, vec3(1.0)), 0.0001);

  float detail = fbm(p * 140.0 + uSeed);
  float coarse = noise(p * 55.0 + uSeed * 1.7);

  vec3 landWeight = sharp * known * (1.0 - water);
  float landSum = dot(landWeight, vec3(1.0));
  vec3 land = vec3(0.4, 0.45, 0.35);
  if (landSum > 0.0001) {
    land = (paletteAt(index.x) * landWeight.x + paletteAt(index.y) * landWeight.y + paletteAt(index.z) * landWeight.z) / landSum;
  }

  float height = regionHeight(qr);
  float rockiness = dot(sharp, rock);
  land = mix(land, vec3(0.47, 0.44, 0.41), rockiness * 0.7);
  land = mix(land, vec3(0.94, 0.95, 0.97), smoothstep(0.82, 0.95, height + detail * 0.12) * rockiness);
  land *= 0.9 + detail * 0.2;

  // Relief: higher than the ground a step toward the sun means lit, lower means shade.
  vec2 sunFlat = vec2(dot(uSun, uEast), -dot(uSun, uNorth));
  float toward = regionHeight(qr + toAxial(sunFlat * 0.35));
  land *= clamp(1.0 + (height - toward) * 3.5, 0.65, 1.35);

  float wet = dot(soft, water) + (coarse - 0.5) * 0.3;
  vec3 sea = mix(vec3(0.1, 0.33, 0.47), vec3(0.04, 0.16, 0.3), smoothstep(0.55, 0.95, wet));
  vec3 ground = mix(land, sea, smoothstep(0.47, 0.53, wet));

  float unknown = dot(soft, 1.0 - known) + (coarse - 0.5) * 0.35;
  return vec4(ground, smoothstep(0.35, 0.65, unknown));
}

// ---- The rest of the planet, made up from the seed ---------------------------------------------------

vec3 backdropGround(vec3 p, vec3 sunPlanet) {
  float sea = 0.5;
  // Two fine octaves keep coasts and ground sharp when the view is zoomed in to plan.
  float fine = noise(p * 38.0 + uSeed) - 0.5;
  float finer = noise(p * 130.0 + uSeed * 1.3) - 0.5;
  float e = fbm(p * 2.1 + uSeed * 0.37) + fine * 0.05 + finer * 0.02;
  e += 0.18 * smoothstep(0.65, 0.2, distance(p, uHome));
  float landShare = smoothstep(sea - 0.004, sea + 0.004, e);
  float height = max(e - sea, 0.0);

  // Mild at the colony's own latitude, as the region is; colder toward either pole.
  float temperature = 0.5 + (abs(uHome.y) - abs(p.y)) * 0.8 + uTemperature + (noise(p * 4.0 + uSeed * 0.53) - 0.5) * 0.25 - height * 1.2;
  float wetness = fbm(p * 3.1 + uSeed * 0.71 + 7.0) + uWetness;
  float w1 = smoothstep(0.38, 0.48, wetness);
  float w2 = smoothstep(0.52, 0.62, wetness);

  vec3 cold = mix(mix(paletteAt(0.0), paletteAt(1.0), w1), paletteAt(2.0), w2);
  vec3 mild = mix(mix(paletteAt(3.0), paletteAt(4.0), w1), paletteAt(5.0), w2);
  vec3 hot = mix(mix(paletteAt(6.0), paletteAt(7.0), w1), paletteAt(8.0), w2);
  vec3 ground = mix(mix(cold, mild, smoothstep(0.28, 0.42, temperature)), hot, smoothstep(0.66, 0.8, temperature));
  ground = mix(ground, vec3(0.45, 0.42, 0.4), smoothstep(0.1, 0.19, height));
  ground = mix(ground, vec3(0.95), smoothstep(0.17, 0.24, height) * smoothstep(0.6, 0.3, temperature));
  ground = mix(ground, vec3(0.93, 0.95, 0.97), smoothstep(0.14, 0.06, temperature));

  float toward = fbm(normalize(p + sunPlanet * 0.012) * 2.1 + uSeed * 0.37);
  ground *= clamp(1.0 + (e - toward) * 26.0, 0.55, 1.35);
  ground *= 1.0 + fine * 0.18 + finer * 0.12;

  vec3 water = mix(vec3(0.02, 0.07, 0.19), vec3(0.07, 0.27, 0.4), smoothstep(sea - 0.14, sea, e));
  water = mix(water, vec3(0.88, 0.92, 0.95), smoothstep(0.1, 0.03, temperature));
  return mix(water, ground, landShare);
}

float clouds(vec3 p) {
  vec3 turned = rotateY(uTime * 0.012) * p;
  float warp = fbm(turned * 5.0 + 3.0);
  return smoothstep(0.5, 0.72, fbm(turned * 2.6 + vec3(0.0, uTime * 0.004, 0.0) + warp * 0.9));
}

void main() {
  vec2 uv = (gl_FragCoord.xy - 0.5 * uResolution) / uRadius;
  float r2 = dot(uv, uv);

  vec2 starCell = floor(gl_FragCoord.xy / 3.0);
  float star = step(0.9975, hash(vec3(starCell, 3.0))) * hash(vec3(starCell, 9.0));
  vec3 colour = vec3(star * 0.8);

  if (r2 >= 1.0) {
    float above = sqrt(r2) - 1.0;
    float lit = smoothstep(-0.5, 0.7, dot(normalize(vec3(uv, 0.0)), uSunView));
    colour += vec3(0.3, 0.55, 1.0) * exp(-above * 22.0) * (0.12 + 0.75 * lit);
    gl_FragColor = vec4(colour, 1.0);
    return;
  }

  vec3 n = vec3(uv, sqrt(1.0 - r2));
  vec3 p = uRotation * n;

  // How far into the backdrop this pixel is: 0 inside the region, 1 two hexes past its rim.
  float fade = 1.0;
  vec4 region = vec4(0.0);
  float facing = dot(p, uHome);
  if (facing > 0.5) {
    vec3 tangent = p / facing - uHome;
    vec2 qr = toAxial(vec2(dot(tangent, uEast), -dot(tangent, uNorth)) / uArc);
    fade = smoothstep(uRegionRadius + 0.5, uRegionRadius + 2.5, hexDistance(qr));
    if (fade < 1.0) {
      region = regionGround(p, qr);
    }
  }

  vec3 surface = region.rgb;
  if (fade > 0.0) {
    surface = mix(region.rgb, backdropGround(p, uSun), fade);
  }

  // The unknown, under its own cloud. Only inside the region: the backdrop is not a secret.
  float fog = region.a * (1.0 - fade);
  float puff = fbm(p * 24.0 + uSeed * 0.29 + uTime * 0.003);
  vec3 fogColour = mix(vec3(0.16, 0.18, 0.22), vec3(0.78, 0.8, 0.84), smoothstep(0.3, 0.75, puff));
  surface = mix(surface, fogColour, fog);

  float cloud = 0.0;
  if (uCloudOpacity > 0.0) {
    cloud = clouds(p) * uCloudOpacity;
    if (uCloudShadows > 0.0) {
      surface *= 1.0 - 0.4 * clouds(normalize(p + uSun * 0.02)) * uCloudOpacity;
    }
  }

  float sunlit = dot(n, uSunView);
  float day = smoothstep(-0.12, 0.22, sunlit);
  float specular = pow(max(dot(reflect(-uSunView, n), vec3(0.0, 0.0, 1.0)), 0.0), 48.0) * (1.0 - cloud);

  colour = mix(surface, vec3(1.0), cloud * 0.92);
  colour = colour * mix(uNightFloor, 1.0, day) + vec3(1.0, 0.95, 0.85) * specular * 0.25 * day;
  colour += vec3(0.9, 0.35, 0.1) * 0.08 * smoothstep(0.25, 0.0, abs(sunlit)) * (1.0 - cloud * 0.5);
  colour += vec3(0.25, 0.5, 1.0) * pow(1.0 - n.z, 3.0) * (0.1 + 0.75 * day);
  colour = mix(colour, vec3(0.3, 0.55, 1.0) * (0.12 + 0.6 * day), smoothstep(0.985, 1.0, sqrt(r2)));
  gl_FragColor = vec4(colour, 1.0);
}
`;
