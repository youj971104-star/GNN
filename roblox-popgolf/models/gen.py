"""팝골프용 로우폴리 3D 모델 생성기 (.obj + .mtl)
- 단위: 스터드(로블록스)
- 부품 이름(o 이름)으로 색을 구분 → 로블록스에서 가져온 뒤 코드가 이름으로 색을 칠할 수도 있음
- 면마다 법선을 따로 줘서 각진(flat) 로우폴리 느낌
"""
import math, os, random
import numpy as np

OUT = os.environ.get("OUT", "out")

COLORS = {
    "Trunk": (0.42, 0.28, 0.17), "Leaves": (0.30, 0.66, 0.30), "LeavesLight": (0.45, 0.78, 0.36),
    "LeavesDark": (0.20, 0.50, 0.26), "Pine": (0.16, 0.48, 0.32), "PineLight": (0.24, 0.60, 0.38),
    "Bush": (0.33, 0.62, 0.30), "Flower": (1.0, 0.45, 0.6),
    "Concrete": (0.36, 0.38, 0.52), "ConcreteLight": (0.48, 0.50, 0.66),
    "SeatRed": (1.0, 0.31, 0.31), "SeatBlue": (0.31, 0.59, 1.0), "SeatWhite": (0.92, 0.93, 0.97),
    "Metal": (0.30, 0.32, 0.38), "Rail": (0.80, 0.82, 0.88), "Neon": (0.24, 0.90, 1.0), "NeonPink": (1.0, 0.28, 0.75),
    "Lamp": (1.0, 0.97, 0.85), "Roof": (0.20, 0.22, 0.34),
}
EMISSIVE = {"Neon", "NeonPink", "Lamp"}


class Mesh:
    def __init__(self, name):
        self.name = name
        self.parts = {}  # part -> list of triangles [(v0,v1,v2), ...] (numpy arrays)

    def tri(self, part, a, b, c):
        self.parts.setdefault(part, []).append((np.array(a, float), np.array(b, float), np.array(c, float)))

    def quad(self, part, a, b, c, d):
        self.tri(part, a, b, c)
        self.tri(part, a, c, d)

    # ---- 기본 도형 ----
    def cylinder(self, part, p0, p1, r0, r1, sides=8, cap=True, twist=0.0):
        p0, p1 = np.array(p0, float), np.array(p1, float)
        axis = p1 - p0
        axis /= np.linalg.norm(axis)
        ref = np.array([1, 0, 0]) if abs(axis[0]) < 0.9 else np.array([0, 0, 1])
        u = np.cross(axis, ref); u /= np.linalg.norm(u)
        v = np.cross(axis, u)
        ring0, ring1 = [], []
        for i in range(sides):
            a = 2 * math.pi * i / sides + twist
            d = u * math.cos(a) + v * math.sin(a)
            ring0.append(p0 + d * r0)
            ring1.append(p1 + d * r1)
        for i in range(sides):
            j = (i + 1) % sides
            if r1 > 1e-4:
                self.quad(part, ring0[i], ring0[j], ring1[j], ring1[i])
            else:
                self.tri(part, ring0[i], ring0[j], p1)
        if cap:
            for i in range(sides):
                j = (i + 1) % sides
                self.tri(part, p0, ring0[j], ring0[i])
                if r1 > 1e-4:
                    self.tri(part, p1, ring1[i], ring1[j])

    def box(self, part, center, size, yaw=0.0, pitch=0.0):
        c = np.array(center, float)
        sx, sy, sz = np.array(size, float) / 2
        cy, syw = math.cos(yaw), math.sin(yaw)
        cp, sp = math.cos(pitch), math.sin(pitch)
        Ry = np.array([[cy, 0, syw], [0, 1, 0], [-syw, 0, cy]])
        Rx = np.array([[1, 0, 0], [0, cp, -sp], [0, sp, cp]])
        R = Ry @ Rx
        corners = {}
        for ix in (-1, 1):
            for iy in (-1, 1):
                for iz in (-1, 1):
                    corners[(ix, iy, iz)] = c + R @ np.array([ix * sx, iy * sy, iz * sz])
        k = corners
        faces = [
            ((1, -1, -1), (1, 1, -1), (1, 1, 1), (1, -1, 1)),
            ((-1, -1, 1), (-1, 1, 1), (-1, 1, -1), (-1, -1, -1)),
            ((-1, 1, -1), (-1, 1, 1), (1, 1, 1), (1, 1, -1)),
            ((-1, -1, 1), (-1, -1, -1), (1, -1, -1), (1, -1, 1)),
            ((-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)),
            ((1, -1, -1), (-1, -1, -1), (-1, 1, -1), (1, 1, -1)),
        ]
        for f in faces:
            self.quad(part, k[f[0]], k[f[1]], k[f[2]], k[f[3]])

    def blob(self, part, center, radius, subdiv=1, jitter=0.14, squash=1.0, seed=0):
        """울퉁불퉁한 로우폴리 구 (잎 덩어리)"""
        t = (1 + 5 ** 0.5) / 2
        verts = [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t),
                 (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]
        verts = [np.array(v, float) / np.linalg.norm(v) for v in verts]
        faces = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6),
                 (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)]
        for _ in range(subdiv):
            cache = {}
            def mid(a, b):
                key = tuple(sorted((a, b)))
                if key not in cache:
                    m = verts[a] + verts[b]
                    verts.append(m / np.linalg.norm(m))
                    cache[key] = len(verts) - 1
                return cache[key]
            nf = []
            for a, b, c in faces:
                ab, bc, ca = mid(a, b), mid(b, c), mid(c, a)
                nf += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
            faces = nf
        rng = random.Random(seed)
        center = np.array(center, float)
        pts = []
        for v in verts:
            r = radius * (1 + rng.uniform(-jitter, jitter))
            p = v * r
            p[1] *= squash
            pts.append(center + p)
        for a, b, c in faces:
            self.tri(part, pts[a], pts[b], pts[c])

    def arc_block(self, part, center, r_in, r_out, a0, a1, y0, y1, segments=12):
        """부채꼴로 휜 블록 (관중석 계단, 곡선 벽)"""
        c = np.array(center, float)
        def P(r, a, y):
            return c + np.array([math.sin(a) * r, y, -math.cos(a) * r])
        for i in range(segments):
            t0 = a0 + (a1 - a0) * i / segments
            t1 = a0 + (a1 - a0) * (i + 1) / segments
            self.quad(part, P(r_in, t0, y1), P(r_out, t0, y1), P(r_out, t1, y1), P(r_in, t1, y1))  # 위
            self.quad(part, P(r_in, t1, y0), P(r_out, t1, y0), P(r_out, t0, y0), P(r_in, t0, y0))  # 아래
            self.quad(part, P(r_in, t0, y0), P(r_in, t0, y1), P(r_in, t1, y1), P(r_in, t1, y0))  # 안쪽
            self.quad(part, P(r_out, t1, y0), P(r_out, t1, y1), P(r_out, t0, y1), P(r_out, t0, y0))  # 바깥
        self.quad(part, P(r_out, a0, y0), P(r_out, a0, y1), P(r_in, a0, y1), P(r_in, a0, y0))
        self.quad(part, P(r_in, a1, y0), P(r_in, a1, y1), P(r_out, a1, y1), P(r_out, a1, y0))

    # ---- 내보내기 ----
    def save(self):
        os.makedirs(OUT, exist_ok=True)
        obj = os.path.join(OUT, self.name + ".obj")
        mtl = os.path.join(OUT, self.name + ".mtl")
        with open(mtl, "w") as f:
            for part in self.parts:
                base = part.rstrip("0123456789")
                r, g, b = COLORS.get(base, (0.8, 0.8, 0.8))
                f.write(f"newmtl {part}\nKd {r:.3f} {g:.3f} {b:.3f}\nKa 0 0 0\n")
                if base in EMISSIVE:
                    f.write(f"Ke {r:.3f} {g:.3f} {b:.3f}\n")
                f.write("\n")
        tris = 0
        with open(obj, "w") as f:
            f.write(f"# PopGolf {self.name}\nmtllib {self.name}.mtl\n")
            vi = 1
            ni = 1
            for part, faces in self.parts.items():
                f.write(f"o {part}\nusemtl {part}\n")
                for a, b, c in faces:
                    n = np.cross(b - a, c - a)
                    ln = np.linalg.norm(n)
                    if ln < 1e-9:
                        continue
                    n /= ln
                    for p in (a, b, c):
                        f.write(f"v {p[0]:.4f} {p[1]:.4f} {p[2]:.4f}\n")
                    f.write(f"vn {n[0]:.4f} {n[1]:.4f} {n[2]:.4f}\n")
                    f.write(f"f {vi}//{ni} {vi+1}//{ni} {vi+2}//{ni}\n")
                    vi += 3
                    ni += 1
                    tris += 1
        print(f"{self.name}: {tris} triangles, parts={list(self.parts)}")


# ---------------------------------------------------------------------------
# 1) 나무 세트
# ---------------------------------------------------------------------------
def tree_round(seed=1):
    m = Mesh("Tree_Round")
    rng = random.Random(seed)
    lean = np.array([rng.uniform(-0.5, 0.5), 0, rng.uniform(-0.5, 0.5)])
    top = np.array([0, 8.5, 0]) + lean
    m.cylinder("Trunk", (0, 0, 0), top, 1.0, 0.55, sides=7)
    # 가지 2개
    for ang, h in ((0.6, 6.0), (3.6, 5.2)):
        p0 = np.array([0, h, 0]) + lean * (h / 8.5)
        p1 = p0 + np.array([math.cos(ang) * 2.2, 1.6, math.sin(ang) * 2.2])
        m.cylinder("Trunk", p0, p1, 0.35, 0.18, sides=5)
    # 잎 덩어리 (색 3단계)
    blobs = [((0, 10.8, 0), 4.2, "Leaves"), ((2.4, 9.6, 1.2), 3.0, "LeavesLight"), ((-2.3, 9.4, -0.8), 3.1, "LeavesDark"),
             ((0.6, 13.0, -0.4), 2.7, "LeavesLight"), ((-0.8, 9.2, 2.4), 2.4, "Leaves")]
    for i, (c, r, part) in enumerate(blobs):
        m.blob(part, np.array(c) + lean, r, subdiv=1, jitter=0.16, squash=0.9, seed=seed * 10 + i)
    m.save()


def tree_pine(seed=2):
    m = Mesh("Tree_Pine")
    m.cylinder("Trunk", (0, 0, 0), (0, 4.5, 0), 0.7, 0.45, sides=6)
    layers = [(2.5, 4.6, 5.0, "Pine"), (5.2, 3.8, 4.6, "PineLight"), (7.7, 3.0, 4.2, "Pine"), (10.0, 2.1, 3.8, "PineLight")]
    for i, (y, r, h, part) in enumerate(layers):
        m.cylinder(part, (0, y, 0), (0, y + h, 0), r, 0.0, sides=8, twist=i * 0.35)
    m.save()


def bush(seed=3):
    m = Mesh("Bush")
    rng = random.Random(seed)
    for i in range(4):
        c = (rng.uniform(-1.6, 1.6), 1.2 + rng.uniform(0, 0.5), rng.uniform(-1.4, 1.4))
        m.blob("Bush" if i % 2 == 0 else "LeavesLight", c, rng.uniform(1.5, 2.1), subdiv=1, jitter=0.18, squash=0.8, seed=seed * 7 + i)
    # 작은 꽃
    for i in range(5):
        a = rng.uniform(0, math.pi * 2)
        c = (math.cos(a) * 2.0, 2.2 + rng.uniform(0, 0.6), math.sin(a) * 1.8)
        m.blob("Flower", c, 0.32, subdiv=0, jitter=0.1, seed=i)
    m.save()


# ---------------------------------------------------------------------------
# 2) 곡선 관중석 한 구역 (60도, 5층) — 의자 색: 왼쪽 레드, 가운데 흰색, 오른쪽 블루
# ---------------------------------------------------------------------------
def stand_section():
    m = Mesh("Stand_Section")
    C = (0, 0, 0)
    a0, a1 = math.radians(-30), math.radians(30)
    R0, depth, step = 30.0, 3.2, 1.4
    tiers = 5
    for i in range(tiers):
        r_in = R0 + i * depth
        part = "Concrete" if i % 2 == 0 else "ConcreteLight"
        m.arc_block(part, C, r_in, r_in + depth, a0, a1, 0, step * (i + 1), segments=14)
        # 의자: 호를 따라 일정 간격
        r_seat = r_in + depth * 0.55
        n = int((a1 - a0) * r_seat / 2.3)
        for k in range(n):
            a = a0 + (a1 - a0) * (k + 0.5) / n
            frac = (a - a0) / (a1 - a0)
            seat = "SeatRed" if frac < 0.36 else ("SeatWhite" if frac < 0.64 else "SeatBlue")
            y = step * (i + 1)
            pos = np.array([math.sin(a) * r_seat, y + 0.35, -math.cos(a) * r_seat])
            back = np.array([math.sin(a) * (r_seat + 0.65), y + 0.95, -math.cos(a) * (r_seat + 0.65)])
            yaw = -a  # 가운데(원점)를 바라봄
            m.box(seat, pos, (1.4, 0.45, 1.2), yaw=yaw)
            m.box(seat, back, (1.4, 1.25, 0.25), yaw=yaw)
    # 앞 난간
    m.arc_block("Rail", C, R0 - 0.35, R0 - 0.1, a0, a1, 1.0, 1.25, segments=14)
    for k in range(9):
        a = a0 + (a1 - a0) * k / 8
        p = (math.sin(a) * (R0 - 0.22), 0, -math.cos(a) * (R0 - 0.22))
        m.cylinder("Rail", p, (p[0], 1.25, p[2]), 0.08, 0.08, sides=5, cap=False)
    # 뒷벽 + 네온 줄
    rb = R0 + tiers * depth
    m.arc_block("Concrete", C, rb, rb + 0.8, a0, a1, 0, step * tiers + 6, segments=14)
    m.arc_block("Neon", C, rb - 0.05, rb, a0, a1, step * tiers + 4.5, step * tiers + 5.0, segments=14)
    m.arc_block("NeonPink", C, rb - 0.05, rb, a0, a1, step * tiers + 2.8, step * tiers + 3.1, segments=14)
    # 지붕 (앞으로 내민 차양) + 기둥
    m.arc_block("Roof", C, R0 + 4, rb + 1.2, a0, a1, step * tiers + 7.5, step * tiers + 8.2, segments=14)
    m.arc_block("Neon", C, R0 + 3.7, R0 + 4.0, a0, a1, step * tiers + 7.5, step * tiers + 8.2, segments=14)
    for k in range(5):
        a = a0 + (a1 - a0) * k / 4
        p = (math.sin(a) * (rb + 0.4), 0, -math.cos(a) * (rb + 0.4))
        m.cylinder("Metal", p, (p[0], step * tiers + 7.6, p[2]), 0.35, 0.35, sides=6)
    m.save()


# ---------------------------------------------------------------------------
# 3) 네온 조명탑 (격자 기둥 + 램프 헤드)
# ---------------------------------------------------------------------------
def light_tower():
    m = Mesh("Light_Tower")
    H = 40.0
    m.box("Concrete", (0, 0.6, 0), (4.4, 1.2, 4.4))
    legs = [(1.6, 1.6), (-1.6, 1.6), (-1.6, -1.6), (1.6, -1.6)]
    top_scale = 0.4
    tops = [(x * top_scale, z * top_scale) for x, z in legs]
    for (x0, z0), (x1, z1) in zip(legs, tops):
        m.cylinder("Metal", (x0, 1.2, z0), (x1, H, z1), 0.22, 0.16, sides=6)
    # 가로·대각 보강재
    for level in range(8):
        y0 = 1.2 + (H - 1.2) * level / 8
        y1 = 1.2 + (H - 1.2) * (level + 1) / 8
        s0 = 1 - (1 - top_scale) * (y0 - 1.2) / (H - 1.2)
        s1 = 1 - (1 - top_scale) * (y1 - 1.2) / (H - 1.2)
        for i in range(4):
            j = (i + 1) % 4
            a0 = np.array([legs[i][0] * s0, y0, legs[i][1] * s0])
            b1 = np.array([legs[j][0] * s1, y1, legs[j][1] * s1])
            b0 = np.array([legs[j][0] * s0, y0, legs[j][1] * s0])
            m.cylinder("Metal", a0, b0, 0.1, 0.1, sides=4, cap=False)
            m.cylinder("Metal", a0, b1, 0.08, 0.08, sides=4, cap=False)
    # 네온 띠 (기둥 중간)
    for y in (12, 24):
        s = 1 - (1 - top_scale) * (y - 1.2) / (H - 1.2)
        m.box("Neon", (0, y, 0), (3.6 * s + 0.4, 0.35, 3.6 * s + 0.4))
    # 램프 헤드: 프레임 + 3x2 램프 (프레임과 함께 12도 숙임 → 램프 위치도 프레임 좌표로 계산)
    pitch = math.radians(-12)
    fc = np.array([0, H + 2.4, 0.4])
    Rx = np.array([[1, 0, 0], [0, math.cos(pitch), -math.sin(pitch)], [0, math.sin(pitch), math.cos(pitch)]])
    def onFrame(local):
        return fc + Rx @ np.array(local, float)
    m.box("Metal", fc, (9.5, 5.4, 1.2), pitch=pitch)
    for ix in range(3):
        for iy in range(2):
            m.box("Lamp", onFrame((-3 + ix * 3, -1.2 + iy * 2.4, -0.72)), (2.5, 1.9, 0.3), pitch=pitch)
    m.box("Neon", onFrame((0, 2.85, -0.2)), (9.7, 0.3, 1.0), pitch=pitch)
    m.box("Neon", onFrame((0, -2.85, -0.2)), (9.7, 0.3, 1.0), pitch=pitch)
    m.save()


if __name__ == "__main__":
    tree_round()
    tree_pine()
    bush()
    stand_section()
    light_tower()
