import { describe, expect, test } from 'bun:test';

import {
  axialDistance,
  clampZoom,
  hexCenter,
  hexCorners,
  MAX_ZOOM,
  MIN_ZOOM,
  panForZoomAt,
  parseCellId,
  regionBounds,
  regionViewBox,
  routePolyline,
  zoomedViewBox,
} from './hexGeometry';

describe('axialDistance', () => {
  test('a cell is zero from itself', () => {
    expect(axialDistance({ q: 0, r: 0 }, { q: 0, r: 0 })).toBe(0);
  });

  test('every neighbour is one step away', () => {
    const neighbours = [
      { q: 1, r: 0 },
      { q: 1, r: -1 },
      { q: 0, r: -1 },
      { q: -1, r: 0 },
      { q: -1, r: 1 },
      { q: 0, r: 1 },
    ];
    for (const neighbour of neighbours) {
      expect(axialDistance({ q: 0, r: 0 }, neighbour)).toBe(1);
    }
  });

  test('diagonals are not counted twice', () => {
    // The case a naive max-of-two-axes implementation gets wrong.
    expect(axialDistance({ q: 0, r: 0 }, { q: 2, r: 2 })).toBe(4);
    expect(axialDistance({ q: 0, r: 0 }, { q: 3, r: -3 })).toBe(3);
    expect(axialDistance({ q: -2, r: 5 }, { q: 1, r: -1 })).toBe(6);
  });

  test('matches the DM implementation it mirrors', () => {
    // These are the exact pairs asserted in rimstation_overworld_axial_distance, so the two sides of the
    // wire cannot disagree about how far apart two cells are.
    expect(axialDistance({ q: 0, r: 0 }, { q: 3, r: 0 })).toBe(3);
    expect(axialDistance({ q: 0, r: 0 }, { q: 0, r: 3 })).toBe(3);
  });
});

describe('hexCenter', () => {
  test('the origin sits at the origin', () => {
    expect(hexCenter({ q: 0, r: 0 }, 10)).toEqual({ x: 0, y: 0 });
  });

  test('a column step moves a full width', () => {
    const center = hexCenter({ q: 1, r: 0 }, 10);
    expect(center.x).toBeCloseTo(Math.sqrt(3) * 10);
    expect(center.y).toBeCloseTo(0);
  });

  test('a row step moves three quarters of a height and half a width', () => {
    const center = hexCenter({ q: 0, r: 1 }, 10);
    expect(center.x).toBeCloseTo((Math.sqrt(3) * 10) / 2);
    expect(center.y).toBeCloseTo(15);
  });

  test('neighbours are all the same distance apart', () => {
    // If this drifts the map renders with visible seams or overlaps.
    const size = 12;
    const origin = hexCenter({ q: 0, r: 0 }, size);
    const neighbours = [
      { q: 1, r: 0 },
      { q: 1, r: -1 },
      { q: 0, r: -1 },
      { q: -1, r: 0 },
      { q: -1, r: 1 },
      { q: 0, r: 1 },
    ];
    const expected = Math.sqrt(3) * size;
    for (const neighbour of neighbours) {
      const point = hexCenter(neighbour, size);
      const gap = Math.hypot(point.x - origin.x, point.y - origin.y);
      expect(gap).toBeCloseTo(expected);
    }
  });
});

describe('hexCorners', () => {
  test('produces six corners', () => {
    expect(hexCorners({ x: 0, y: 0 }, 10)).toHaveLength(6);
  });

  test('is pointy-top: the first corner is directly above the centre', () => {
    const [top] = hexCorners({ x: 0, y: 0 }, 10);
    expect(top.x).toBeCloseTo(0);
    expect(top.y).toBeCloseTo(-10);
  });

  test('every corner is one size from the centre', () => {
    for (const corner of hexCorners({ x: 5, y: 7 }, 9)) {
      expect(Math.hypot(corner.x - 5, corner.y - 7)).toBeCloseTo(9);
    }
  });
});

describe('regionViewBox', () => {
  test('grows with the region', () => {
    const compact = regionViewBox(7, 10).split(' ').map(Number);
    const expansive = regionViewBox(11, 10).split(' ').map(Number);
    expect(expansive[2]).toBeGreaterThan(compact[2]);
    expect(expansive[3]).toBeGreaterThan(compact[3]);
  });

  test('is centred on the colony', () => {
    const [minX, minY, width, height] = regionViewBox(9, 10).split(' ').map(Number);
    expect(minX + width / 2).toBeCloseTo(0);
    expect(minY + height / 2).toBeCloseTo(0);
  });

  test('contains the outermost cell of the region', () => {
    const radius = 9;
    const size = 10;
    const [minX, minY, width, height] = regionViewBox(radius, size).split(' ').map(Number);
    // The furthest cell along each axis must fall inside the box, corners included.
    for (const cell of [
      { q: radius, r: 0 },
      { q: -radius, r: 0 },
      { q: 0, r: radius },
      { q: 0, r: -radius },
    ]) {
      const center = hexCenter(cell, size);
      expect(center.x).toBeGreaterThanOrEqual(minX);
      expect(center.x).toBeLessThanOrEqual(minX + width);
      expect(center.y).toBeGreaterThanOrEqual(minY);
      expect(center.y).toBeLessThanOrEqual(minY + height);
    }
  });
});

describe('routePolyline', () => {
  test('is empty for no cells', () => {
    expect(routePolyline([], 10)).toBe('');
  });

  test('produces one point per cell', () => {
    const points = routePolyline([{ q: 0, r: 0 }, { q: 1, r: 0 }, { q: 2, r: 0 }], 10);
    expect(points.split(' ')).toHaveLength(3);
  });
});

describe('clampZoom', () => {
  test('holds the usable range', () => {
    expect(clampZoom(0.1)).toBe(MIN_ZOOM);
    expect(clampZoom(1000)).toBe(MAX_ZOOM);
    expect(clampZoom(3)).toBe(3);
  });
});

describe('zoomedViewBox', () => {
  const base = regionBounds(9, 10);

  test('at minimum zoom it shows the whole region', () => {
    const box = zoomedViewBox(base, MIN_ZOOM, 0, 0);
    expect(box.width).toBeCloseTo(base.width);
    expect(box.height).toBeCloseTo(base.height);
  });

  test('zooming in shows less of the region', () => {
    const near = zoomedViewBox(base, 4, 0, 0);
    expect(near.width).toBeLessThan(base.width);
    expect(near.height).toBeLessThan(base.height);
  });

  test('stays centred when not panned', () => {
    const box = zoomedViewBox(base, 3, 0, 0);
    expect(box.x + box.width / 2).toBeCloseTo(0);
    expect(box.y + box.height / 2).toBeCloseTo(0);
  });

  test('panning cannot lose the region entirely', () => {
    // However far the pan is pushed, part of the region must remain in frame.
    const box = zoomedViewBox(base, 4, 99999, 99999);
    expect(box.x).toBeLessThan(base.x + base.width);
    expect(box.y).toBeLessThan(base.y + base.height);

    const other = zoomedViewBox(base, 4, -99999, -99999);
    expect(other.x + other.width).toBeGreaterThan(base.x);
    expect(other.y + other.height).toBeGreaterThan(base.y);
  });
});

describe('panForZoomAt', () => {
  const base = regionBounds(9, 10);

  test('keeps the point under the cursor still', () => {
    const fromZoom = 1;
    const toZoom = 3;
    const fractionX = 0.25;
    const fractionY = 0.75;

    const before = zoomedViewBox(base, fromZoom, 0, 0);
    const anchorX = before.x + before.width * fractionX;
    const anchorY = before.y + before.height * fractionY;

    const pan = panForZoomAt(base, fromZoom, toZoom, 0, 0, fractionX, fractionY);
    const after = zoomedViewBox(base, toZoom, pan.x, pan.y);

    expect(after.x + after.width * fractionX).toBeCloseTo(anchorX, 1);
    expect(after.y + after.height * fractionY).toBeCloseTo(anchorY, 1);
  });

  test('zooming at the centre does not drift', () => {
    const pan = panForZoomAt(base, 1, 4, 0, 0, 0.5, 0.5);
    expect(pan.x).toBeCloseTo(0);
    expect(pan.y).toBeCloseTo(0);
  });
});

describe('parseCellId', () => {
  test('reads the backend id format', () => {
    expect(parseCellId('3,-2')).toEqual({ q: 3, r: -2 });
    expect(parseCellId('0,0')).toEqual({ q: 0, r: 0 });
  });

  test('refuses anything else rather than throwing', () => {
    expect(parseCellId('')).toBeNull();
    expect(parseCellId('3')).toBeNull();
    expect(parseCellId('3,2,1')).toBeNull();
    expect(parseCellId('east,north')).toBeNull();
  });
});
