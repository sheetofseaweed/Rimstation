/**
 * Pure geometry for the overworld globe: where the region sits on the planet, how hexes map onto the
 * sphere and back, the view rotation, the sun, and the packed cell texture the shader reads.
 *
 * Kept free of React and WebGL so it can be tested on its own.
 */

export type Vec3 = [number, number, number];
/** Column-major 3x3 matrix, as WebGL takes it. */
export type Mat3 = [
  number,
  number,
  number,
  number,
  number,
  number,
  number,
  number,
  number,
];

/** Radians of planet surface per hex size unit. The largest region then spans about 48 degrees. */
export const GLOBE_ARC = 0.02;

/** Hexes of extra data packed around the region, so the shader can fade into the backdrop. */
export const CELL_TEXTURE_MARGIN = 3;

/** Shader index of each terrain. Must match the order the fragment shader's palette texture uses. */
export const TERRAIN_ORDER = [
  'frozen_steppe',
  'tundra',
  'taiga',
  'scrubland',
  'grassland',
  'forest',
  'desert',
  'savanna',
  'marsh',
  'water',
];
export const WATER_INDEX = TERRAIN_ORDER.indexOf('water');
/** Terrain byte for a hex the colony has not seen. */
export const UNKNOWN_TERRAIN = 255;

/** Lit colours for the globe, one per entry of TERRAIN_ORDER. Brighter than the flat map's fills. */
export const GLOBE_PALETTE: Vec3[] = [
  [0.78, 0.82, 0.85],
  [0.6, 0.66, 0.62],
  [0.3, 0.44, 0.33],
  [0.62, 0.6, 0.4],
  [0.45, 0.6, 0.3],
  [0.2, 0.38, 0.21],
  [0.82, 0.71, 0.48],
  [0.7, 0.6, 0.33],
  [0.34, 0.42, 0.34],
  [0.08, 0.27, 0.42],
];

const TOPOLOGY_ORDER = ['easy', 'normal', 'difficult', 'impassable'];

export const normalize = (v: Vec3): Vec3 => {
  const length = Math.hypot(v[0], v[1], v[2]) || 1;
  return [v[0] / length, v[1] / length, v[2] / length];
};

export const dot = (a: Vec3, b: Vec3): number =>
  a[0] * b[0] + a[1] * b[1] + a[2] * b[2];

export const cross = (a: Vec3, b: Vec3): Vec3 => [
  a[1] * b[2] - a[2] * b[1],
  a[2] * b[0] - a[0] * b[2],
  a[0] * b[1] - a[1] * b[0],
];

/** A unit vector from latitude and longitude in radians. Y is the planet's axis. */
export function fromLatLon(lat: number, lon: number): Vec3 {
  return [
    Math.cos(lat) * Math.sin(lon),
    Math.sin(lat),
    Math.cos(lat) * Math.cos(lon),
  ];
}

export type RegionFrame = {
  lat: number;
  lon: number;
  home: Vec3;
  east: Vec3;
  north: Vec3;
};

/**
 * Where the colony stands on its planet, from the planet's seed.
 *
 * Always in the northern temperate band, so the south of the region faces the equator - which is the
 * direction the server's climate already makes warmer.
 */
export function regionFrame(seed: number): RegionFrame {
  const value = Math.abs(Math.floor(seed)) || 1;
  const lat = 0.2 + ((value % 997) / 997) * 0.45;
  const lon = (((Math.floor(value / 997) % 991) / 991) * 2 - 1) * Math.PI;
  const home = fromLatLon(lat, lon);
  const east = normalize(cross([0, 1, 0], home));
  const north = cross(home, east);
  return { lat, lon, home, east, north };
}

/** Flat position of a hex centre, in hex size units. Pointy-top, as the flat map draws it. */
export function hexFlat(q: number, r: number): [number, number] {
  return [Math.sqrt(3) * (q + r / 2), 1.5 * r];
}

/** Fractional axial coordinates of a flat position. */
export function flatToAxial(x: number, y: number): [number, number] {
  const r = y / 1.5;
  return [x / Math.sqrt(3) - r / 2, r];
}

/** A flat map position on the sphere. Positive y is south, as on the flat map. */
export function flatToSphere(frame: RegionFrame, x: number, y: number): Vec3 {
  const { home, east, north } = frame;
  return normalize([
    home[0] + (east[0] * x - north[0] * y) * GLOBE_ARC,
    home[1] + (east[1] * x - north[1] * y) * GLOBE_ARC,
    home[2] + (east[2] * x - north[2] * y) * GLOBE_ARC,
  ]);
}

/** The inverse of flatToSphere, for points facing the colony. Null for the far side. */
export function sphereToFlat(
  frame: RegionFrame,
  point: Vec3,
): [number, number] | null {
  const facing = dot(point, frame.home);
  if (facing <= 0.05) {
    return null;
  }
  const tangent: Vec3 = [
    point[0] / facing - frame.home[0],
    point[1] / facing - frame.home[1],
    point[2] / facing - frame.home[2],
  ];
  return [
    dot(tangent, frame.east) / GLOBE_ARC,
    -dot(tangent, frame.north) / GLOBE_ARC,
  ];
}

/** Rounds fractional axial coordinates to the hex that contains them. */
export function roundAxial(q: number, r: number): [number, number] {
  const s = -q - r;
  let rq = Math.round(q);
  let rr = Math.round(r);
  const rs = Math.round(s);
  const dq = Math.abs(rq - q);
  const dr = Math.abs(rr - r);
  const ds = Math.abs(rs - s);
  if (dq > dr && dq > ds) {
    rq = -rr - rs;
  } else if (dr > ds) {
    rr = -rq - rs;
  }
  // Avoids -0, which would print as a different cell id.
  return [rq + 0, rr + 0];
}

/** Hex distance from the colony, for fractional coordinates too. */
export function hexDistance(q: number, r: number): number {
  return Math.max(Math.abs(q), Math.abs(r), Math.abs(q + r));
}

/** View to planet rotation: yaw about the axis, then pitch. */
export function viewRotation(yaw: number, pitch: number): Mat3 {
  const cy = Math.cos(yaw);
  const sy = Math.sin(yaw);
  const cp = Math.cos(pitch);
  const sp = Math.sin(pitch);
  return [cy, 0, -sy, sy * sp, cp, cy * sp, sy * cp, -sp, cy * cp];
}

/** The yaw and pitch that put a point in the middle of the view with its north up. */
export function viewFacing(lat: number, lon: number): {
  yaw: number;
  pitch: number;
} {
  return { yaw: lon, pitch: -lat };
}

/** Planet space to view space: the transpose of the view rotation. */
export function toView(rotation: Mat3, p: Vec3): Vec3 {
  return [
    rotation[0] * p[0] + rotation[1] * p[1] + rotation[2] * p[2],
    rotation[3] * p[0] + rotation[4] * p[1] + rotation[5] * p[2],
    rotation[6] * p[0] + rotation[7] * p[1] + rotation[8] * p[2],
  ];
}

/**
 * The sun's direction in planet space, from the colony's day fraction (0 midnight, 0.5 noon).
 *
 * At noon the sun stands over the colony's meridian. In the morning it is east of it.
 */
export function sunDirection(frame: RegionFrame, dayFraction: number): Vec3 {
  const lon = frame.lon + (0.5 - dayFraction) * 2 * Math.PI;
  return fromLatLon(0.25, lon);
}

export type PackedCell = {
  q: number;
  r: number;
  terrain?: string;
  topology?: string;
  height?: number;
};

/**
 * Packs the region into an RGBA texture, one texel per hex: terrain, height, topology, known flag.
 *
 * Texel (i, j) holds hex (i - offset, j - offset). Texels outside the region copy the nearest edge hex, so
 * the shader can blend past the region's rim into the backdrop without a seam.
 */
export function packCellTexture(
  radius: number,
  cells: PackedCell[],
): { size: number; offset: number; data: Uint8Array } {
  const offset = radius + CELL_TEXTURE_MARGIN;
  const size = offset * 2 + 1;
  const data = new Uint8Array(size * size * 4);

  const byId: Record<string, PackedCell> = {};
  for (const cell of cells) {
    byId[`${cell.q},${cell.r}`] = cell;
  }

  for (let j = 0; j < size; j++) {
    for (let i = 0; i < size; i++) {
      let q = i - offset;
      let r = j - offset;
      const distance = hexDistance(q, r);
      if (distance > radius) {
        // Pulled straight back toward the colony until it lands on the rim.
        [q, r] = roundAxial(
          (q * radius) / distance,
          (r * radius) / distance,
        );
      }
      const cell = byId[`${q},${r}`];
      const texel = (j * size + i) * 4;
      const terrain = cell?.terrain ? TERRAIN_ORDER.indexOf(cell.terrain) : -1;
      if (terrain < 0) {
        data[texel] = UNKNOWN_TERRAIN;
        data[texel + 3] = 0;
        continue;
      }
      data[texel] = terrain;
      data[texel + 1] = Math.round(
        (Math.max(0, Math.min(99, cell?.height ?? 40)) / 99) * 255,
      );
      data[texel + 2] = Math.max(
        0,
        TOPOLOGY_ORDER.indexOf(cell?.topology ?? 'easy') * 85,
      );
      data[texel + 3] = 255;
    }
  }
  return { size, offset, data };
}

/** The zoom that fits the whole region in view, as a share of the smaller screen side. */
export function regionFitZoom(radius: number): number {
  const angle = GLOBE_ARC * Math.sqrt(3) * (radius + 1);
  return 0.46 / Math.max(0.05, Math.sin(angle));
}

/** A number from a string, stable across sessions. Used to seed the backdrop when no seed is sent. */
export function seedFromText(text: string): number {
  let hash = 2166136261;
  for (let index = 0; index < text.length; index++) {
    hash ^= text.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0) % 1000000;
}
