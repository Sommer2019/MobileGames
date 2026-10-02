import 'dart:math';
import 'dart:ui';

/// Orientation of a ball rolling on a table, for drawing it turning.
///
/// Two perpendicular unit vectors are tracked: [q] (e.g. where a number
/// sits) and [a] (e.g. the axis of a stripe). x/y are like the screen,
/// z points up towards the viewer.
class SphereOrientation {
  SphereOrientation({double axisAngle = 0}) {
    ax = cos(axisAngle);
    ay = sin(axisAngle);
  }

  double qx = 0, qy = 0, qz = 1;
  double ax = 1, ay = 0, az = 0;

  /// Third axis, perpendicular to [q] and [a].
  (double, double, double) get b =>
      (qy * az - qz * ay, qz * ax - qx * az, qx * ay - qy * ax);

  /// Rolls a ball of [radius] over the distance (dx, dy) without slipping.
  void roll(double dx, double dy, double radius) {
    final d = sqrt(dx * dx + dy * dy);
    if (d == 0) return;
    // Axis lies on the table, perpendicular to the motion.
    final kx = -dy / d, ky = dx / d;
    final angle = d / radius;
    final c = cos(angle), s = sin(angle);
    (double, double, double) rot(double px, double py, double pz) {
      // Rodrigues' rotation with k = (kx, ky, 0).
      final cx = ky * pz, cy = -kx * pz, cz = kx * py - ky * px;
      final dot = kx * px + ky * py;
      final rx = px * c + cx * s + kx * dot * (1 - c);
      final ry = py * c + cy * s + ky * dot * (1 - c);
      final rz = pz * c + cz * s;
      final n = sqrt(rx * rx + ry * ry + rz * rz);
      return (rx / n, ry / n, rz / n);
    }

    final nq = rot(qx, qy, qz), na = rot(ax, ay, az);
    qx = nq.$1;
    qy = nq.$2;
    qz = nq.$3;
    ax = na.$1;
    ay = na.$2;
    az = na.$3;
  }

  /// Outline of a spherical cap around the unit vector (x, y, z) with the
  /// angular radius [alpha] (< π/2) on a ball at [c] with radius [r], seen
  /// from above. Parts on the far side are pushed onto the outline of the
  /// ball. Null if nothing of it is visible.
  static Path? capPath(
    Offset c,
    double r,
    double qx,
    double qy,
    double qz,
    double alpha,
  ) {
    // Two vectors perpendicular to q.
    var ux = -qy, uy = qx;
    var len = sqrt(ux * ux + uy * uy);
    if (len < 1e-6) {
      ux = 1;
      uy = 0;
      len = 1;
    }
    ux /= len;
    uy /= len;
    final wx = -qz * uy;
    final wy = qz * ux;
    final wz = qx * uy - qy * ux;
    final ca = cos(alpha), sa = sin(alpha);
    final path = Path();
    var visible = false;
    const n = 28;
    for (var i = 0; i < n; i++) {
      final t = i * 2 * pi / n;
      final ct = cos(t), st = sin(t);
      var x = qx * ca + (ux * ct + wx * st) * sa;
      var y = qy * ca + (uy * ct + wy * st) * sa;
      final z = qz * ca + wz * st * sa;
      if (z >= 0) {
        visible = true;
      } else {
        final l = sqrt(x * x + y * y);
        if (l > 1e-6) {
          x /= l;
          y /= l;
        }
      }
      final pt = c + Offset(x, y) * r;
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    return visible ? (path..close()) : null;
  }
}
