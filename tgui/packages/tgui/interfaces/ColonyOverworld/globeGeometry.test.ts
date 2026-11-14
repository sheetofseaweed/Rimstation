import { describe, expect, test } from 'bun:test';

import {
  CELL_TEXTURE_MARGIN,
  dot,
  flatToAxial,
  flatToSphere,
  hexFlat,
  packCellTexture,
  regionFrame,
  roundAxial,
  sphereToFlat,
  sunDirection,
  TERRAIN_ORDER,
  toView,
  UNKNOWN_TERRAIN,
  viewFacing,
  viewRotation,
} from './globeGeometry';

const frame = regionFrame(424242);

describe('regionFrame', () => {
  test('the colony stands in the northern temperate band', () => {
    for (const seed of [1, 999, 123456, 999999]) {
      const { lat } = regionFrame(seed);
      expect(lat).toBeGreaterThan(0.15);
      expect(lat).toBeLessThan(0.7);
    }
  });

  test('east, north and home are a right-handed unit frame', () => {
    expect(dot(frame.home, frame.east)).toBeCloseTo(0, 6);
    expect(dot(frame.home, frame.north)).toBeCloseTo(0, 6);
    expect(dot(frame.east, frame.north)).toBeCloseTo(0, 6);
    expect(frame.north[1]).toBeGreaterThan(0);
  });
});

describe('sphere mapping', () => {
  test('a hex centre maps onto the sphere and back to itself', () => {
    for (const [q, r] of [
      [0, 0],
      [3, -1],
      [-7, 4],
      [11, -11],
    ]) {
      const [x, y] = hexFlat(q, r);
      const back = sphereToFlat(frame, flatToSphere(frame, x, y));
      expect(back).not.toBeNull();
      const [bq, br] = flatToAxial(back![0], back![1]);
      expect(roundAxial(bq, br)).toEqual([q, r]);
      expect(bq).toBeCloseTo(q, 6);
      expect(br).toBeCloseTo(r, 6);
    }
  });

  test('the far side of the planet has no flat position', () => {
    const away: [number, number, number] = [
      -frame.home[0],
      -frame.home[1],
      -frame.home[2],
    ];
    expect(sphereToFlat(frame, away)).toBeNull();
  });

  test('a point just inside a hex rounds to that hex', () => {
    const [x, y] = hexFlat(2, 3);
    const [q, r] = flatToAxial(x + 0.4, y - 0.3);
    expect(roundAxial(q, r)).toEqual([2, 3]);
  });
});

describe('view', () => {
  test('facing the colony puts it in the centre with north up and east right', () => {
    const { yaw, pitch } = viewFacing(frame.lat, frame.lon);
    const rotation = viewRotation(yaw, pitch);
    const centre = toView(rotation, frame.home);
    expect(centre[0]).toBeCloseTo(0, 6);
    expect(centre[1]).toBeCloseTo(0, 6);
    expect(centre[2]).toBeCloseTo(1, 6);

    const north = toView(rotation, flatToSphere(frame, 0, -3));
    const east = toView(rotation, flatToSphere(frame, 3, 0));
    expect(north[1]).toBeGreaterThan(0);
    expect(east[0]).toBeGreaterThan(0);
  });
});

describe('sunDirection', () => {
  test('the sun is over the colony at noon and behind the planet at midnight', () => {
    expect(dot(sunDirection(frame, 0.5), frame.home)).toBeGreaterThan(0.8);
    expect(dot(sunDirection(frame, 0), frame.home)).toBeLessThan(-0.4);
  });

  test('the morning sun is east of the colony', () => {
    expect(dot(sunDirection(frame, 0.3), frame.east)).toBeGreaterThan(0.3);
  });
});

describe('packCellTexture', () => {
  const radius = 2;
  const cells = [
    { q: 0, r: 0, terrain: 'grassland', topology: 'easy', height: 30 },
    { q: 2, r: 0, terrain: 'water', topology: 'impassable', height: 5 },
    { q: -2, r: 0 },
  ];
  const { size, offset, data } = packCellTexture(radius, cells);
  const texel = (q: number, r: number) =>
    Array.from(
      data.slice(
        ((r + offset) * size + (q + offset)) * 4,
        ((r + offset) * size + (q + offset)) * 4 + 4,
      ),
    );

  test('the texture covers the region and its margin', () => {
    expect(offset).toBe(radius + CELL_TEXTURE_MARGIN);
    expect(size).toBe(offset * 2 + 1);
  });

  test('a known hex carries its terrain, height, topology and known flag', () => {
    expect(texel(0, 0)).toEqual([
      TERRAIN_ORDER.indexOf('grassland'),
      Math.round((30 / 99) * 255),
      0,
      255,
    ]);
    expect(texel(2, 0)[0]).toBe(TERRAIN_ORDER.indexOf('water'));
    expect(texel(2, 0)[2]).toBe(255);
  });

  test('an unseen hex is marked unknown', () => {
    expect(texel(-2, 0)[0]).toBe(UNKNOWN_TERRAIN);
    expect(texel(-2, 0)[3]).toBe(0);
    expect(texel(1, 1)[0]).toBe(UNKNOWN_TERRAIN);
  });

  test('outside the region the rim hex is copied outward', () => {
    expect(texel(4, 0)).toEqual(texel(2, 0));
    expect(texel(-5, 0)).toEqual(texel(-2, 0));
  });
});
