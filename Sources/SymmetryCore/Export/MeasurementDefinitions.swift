import Foundation

/// Human-readable definitions of every reported quantity. Exported with each report so a
/// reader never has to guess what a number means.
public enum MeasurementDefinitions {
    public static let markdown: String = """
    # Measurement definitions

    All frontal measurements are computed from hand-placed landmarks in a normalized
    midline frame. The frame is built from two landmarks: the sternal notch and the
    midline bottom (xiphoid or umbilicus, used consistently within a study). The
    landmark set is translated so the sternal notch is the origin, rotated so the
    midline points straight down, and scaled so the notch-to-midline-bottom distance,
    the reference length L, equals 1. Values are therefore fractions of L. Pixel values
    are reported alongside for traceability. "Left" and "right" are the patient's sides.

    - Vertical nipple difference: (y of patient-left nipple − y of patient-right nipple) / L.
      Positive means the patient's left nipple sits lower in the image.
    - Patient left nipple to midline: horizontal distance of the patient-left nipple from
      the midline / L.
    - Patient right nipple to midline: horizontal distance of the patient-right nipple from
      the midline / L.
    - Nipple to midline difference: left distance − right distance. Positive means the
      patient's left nipple is farther from the midline.
    - Inframammary fold height difference: (y of patient-left fold − y of patient-right
      fold) / L. Positive means the patient's left fold sits lower.
    - Contour overlap: Dice coefficient between the patient-left breast contour and the
      patient-right contour mirrored across the midline, on a 256 × 256 raster. 1 means
      identical silhouettes; reported only when both contours have at least 8 points.

    Uncertainty: each landmark is assumed to carry an isotropic placement standard
    deviation of sigma × L (default sigma = 0.015). A difference of two landmarks has
    uncertainty sigma × √2; a single distance has uncertainty sigma. Changes between two
    capture sets combine the two uncertainties in quadrature. The placement uncertainty of
    the two midline landmarks themselves, which shifts the whole frame, is not included;
    the registration residual is reported as a separate check on frame stability.

    Registration: the current landmark set is mapped onto the baseline set by a
    least-squares 2D similarity transform (scale, rotation, translation) over the shared
    point landmarks. The root-mean-square residual divided by L is the registration
    residual; above the threshold (default 0.05) the comparison is flagged unreliable.

    Quality: blur is the variance of a 3 × 3 Laplacian on a downsampled luminance image;
    exposure is the fraction of pixels clipped at either end; tilt is the phone's
    orientation from its motion sensors at the moment of capture, which describes the
    phone, not the camera's pose relative to the patient.

    ## Limitations

    - No physical calibration exists, so no value is a millimetre, a volume, or a
      percentage of symmetry. Ratios depend on a consistent choice of midline landmarks.
    - Handheld photographs carry perspective, parallax, lens distortion, rotation and
      distance variability. Landmark-based similarity registration does not remove
      perspective or pose changes that the six landmarks do not capture.
    - Oblique views are descriptive only; the two sides are never in one oblique image.
    - Three 2D views are not a volumetric reconstruction.
    - The prototype is not clinically validated and makes no treatment suggestions.
    """
}
