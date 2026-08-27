/**
 * Pure axial-hex geometry for the overworld map.
 *
 * Kept free of React and of any backend type so it can be tested on its own. Everything here is a pointy-top
 * layout: hexes have a vertex at the top, neighbours sit east/west, and rows interlock horizontally.
 */

export type Axial = { q: number; r: number };
export type Point = { x: number; y: number };

/** Distance in whole hexes between two axial coordinates. */
export function axialDistance(a: Axial, b: Axial): number {
  const dq = a.q - b.q;
  const dr = a.r - b.r;
  const ds = -a.q - a.r - (-b.q - b.r);
  return Math.max(Math.abs(dq), Math.abs(dr), Math.abs(ds));
}

/**
 * Centre of a hex in SVG units.
 *
 * The pointy-top conversion: a column step moves a full width, and a row step moves three quarters of a
 * height while shifting half a width, which is what makes rows interlock.
 */
export function hexCenter(cell: Axial, size: number): Point {
  const width = Math.sqrt(3) * size;
  const height = 2 * size;
  return {
    x: width * (cell.q + cell.r / 2),
    y: height * (3 / 4) * cell.r,
  };
}

/** The six corners of a hex, starting at the top vertex and going clockwise. */
export function hexCorners(center: Point, size: number): Point[] {
  const corners: Point[] = [];
  for (let corner = 0; corner < 6; corner++) {
    // -90 degrees puts the first vertex at the top, which is what makes this pointy-top rather than flat-top.
    const angle = (Math.PI / 180) * (60 * corner - 90);
    corners.push({
      x: center.x + size * Math.cos(angle),
      y: center.y + size * Math.sin(angle),
    });
  }
  return corners;
}

/** A hex as an SVG `points` attribute. */
export function hexPoints(cell: Axial, size: number): string {
  return hexCorners(hexCenter(cell, size), size)
    .map((point) => `${round(point.x)},${round(point.y)}`)
    .join(' ');
}

export type ViewBox = { x: number; y: number; width: number; height: number };

/** How far in and out the map may be scaled. Beyond these the map stops being usable in either direction. */
export const MIN_ZOOM = 1;
export const MAX_ZOOM = 8;

/**
 * The bounds that contain a whole region of the given radius, with room for the outermost hexes' corners.
 *
 * Computed from the geometry rather than guessed, so compact and expansive regions both fill the frame instead
 * of one being cramped and the other lost in whitespace. Always centred on the colony at the origin.
 */
export function regionBounds(radius: number, size: number, padding = 4): ViewBox {
  const width = Math.sqrt(3) * size;
  const height = 2 * size;

  // The widest row is the middle one, and it is offset by half a width per row of the radius.
  const halfWidth = width * (radius + radius / 2) + width / 2 + padding;
  const halfHeight = height * (3 / 4) * radius + height / 2 + padding;

  return {
    x: -halfWidth,
    y: -halfHeight,
    width: halfWidth * 2,
    height: halfHeight * 2,
  };
}

/** A ViewBox as an SVG `viewBox` attribute. */
export function formatViewBox(box: ViewBox): string {
  return `${round(box.x)} ${round(box.y)} ${round(box.width)} ${round(box.height)}`;
}

/** Convenience for the un-zoomed, un-panned view of a whole region. */
export function regionViewBox(radius: number, size: number, padding = 4): string {
  return formatViewBox(regionBounds(radius, size, padding));
}

export function clampZoom(zoom: number): number {
  return Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, zoom));
}

/**
 * The visible box at a given zoom and pan.
 *
 * Zoom divides the base extent, so a larger zoom shows less of the region. Pan moves the centre in SVG units,
 * and is clamped so the region can never be scrolled entirely off screen - being lost in empty space with no
 * way back is a worse outcome than not being able to reach a corner.
 */
export function zoomedViewBox(base: ViewBox, zoom: number, panX: number, panY: number): ViewBox {
  const safeZoom = clampZoom(zoom);
  const width = base.width / safeZoom;
  const height = base.height / safeZoom;

  // At most half the visible frame may hang past the region's edge.
  const limitX = Math.max(0, base.width / 2 - width / 2) + width / 4;
  const limitY = Math.max(0, base.height / 2 - height / 2) + height / 4;
  const centerX = Math.min(limitX, Math.max(-limitX, panX));
  const centerY = Math.min(limitY, Math.max(-limitY, panY));

  return {
    x: centerX - width / 2,
    y: centerY - height / 2,
    width,
    height,
  };
}

/**
 * The pan that keeps the point under the cursor still while zooming.
 *
 * Without this, zooming walks toward the centre of the region and the thing you were looking at slides away,
 * which is the difference between a map that feels examined and one that feels fought.
 *
 * `fractionX`/`fractionY` are the cursor's position within the drawn area, 0 to 1.
 */
export function panForZoomAt(
  base: ViewBox,
  fromZoom: number,
  toZoom: number,
  panX: number,
  panY: number,
  fractionX: number,
  fractionY: number,
): { x: number; y: number } {
  const before = zoomedViewBox(base, fromZoom, panX, panY);
  // The SVG point currently under the cursor.
  const anchorX = before.x + before.width * fractionX;
  const anchorY = before.y + before.height * fractionY;

  const safeZoom = clampZoom(toZoom);
  const width = base.width / safeZoom;
  const height = base.height / safeZoom;

  // Solve for the centre that puts the same point back under the same fraction of the frame.
  return {
    x: anchorX - width * fractionX + width / 2,
    y: anchorY - height * fractionY + height / 2,
  };
}

/** A polyline through the centres of a sequence of cells, for drawing a route. */
export function routePolyline(cells: Axial[], size: number): string {
  return cells
    .map((cell) => {
      const center = hexCenter(cell, size);
      return `${round(center.x)},${round(center.y)}`;
    })
    .join(' ');
}

/** Parses the backend's `"q,r"` cell id. Returns null rather than throwing on anything unexpected. */
export function parseCellId(id: string): Axial | null {
  const parts = id.split(',');
  if (parts.length !== 2) {
    return null;
  }
  const q = Number(parts[0]);
  const r = Number(parts[1]);
  if (!Number.isFinite(q) || !Number.isFinite(r)) {
    return null;
  }
  return { q, r };
}

/** Trims float noise so SVG attributes stay short and stable between renders. */
function round(value: number): number {
  return Math.round(value * 100) / 100;
}
