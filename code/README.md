# InterShear – MATLAB Toolbox for Generating Synthetic Shearography Data and Calculating Displacement Gradients

**InterShear** is a MATLAB class designed to generate **synthetic shearographic phase maps** from *out-of-plane displacement fields* obtained from **finite element simulations**. It operates exclusively on **ANSYS export files** and converts the simulation data into smoothed, rasterized fields suitable for optical shearography analysis.

This toolbox is part of the numerical framework accompanying the following peer-reviewed publication:

**Plassmann, J., Schuth, M., & von Freymann, G. (2025).**  
*Simulation of Speckle Interferometric Results for Enhanced Measurement and Automated Defect Detection.*  
**Optics Express, 33(24), 50791–50800.**  
https://doi.org/10.1364/OE.572513  
_Preprint available at arXiv:2507.00732_


## Key Features

- Import of **displacement data**
- Automatic recognition of German and English decimal separators
- Coordinate transformation and optional region cropping
- Interpolation onto a uniform camera-like grid
- Gaussian filtering to suppress numerical noise
- Computation of displacement gradients (**dwdx**, **dwdy**)
- Generation of **synthetic shearography-like phase maps** through remodulation
- Automated plotting and structured session management


## Input Format

InterShear requires input files with the following column structure:

| Column | Description                          |
|--------|--------------------------------------|
| 1      | X-coordinate [mm]                    |
| 2      | Y-coordinate [mm]                    |
| 3      | Z-coordinate [mm]                    |
| 4      | Out-of-plane displacement *w* [mm]   |

This column order corresponds to the default export format from ANSYS, but data from any other software can be used as long as it is parsed to match this structure.

## Installation

Requirements:

- MATLAB R2022b or newer  
- Image Processing Toolbox  
- No additional dependencies

Add the toolbox folder to your MATLAB path:

```matlab
addpath("path/to/InterShear/");
```

## Example Usage
Below are several example calls demonstrating different workflows and use cases of the `InterShear` class.

### Basic Data Import
```matlab
% Create object (empty constructor)
obj = InterShear();

% Import ANSYS reference and measurement data
obj.DataImporter('test_ref.txt', 'test_meas.txt', 'de');
```

### Full Workflow

```matlab
% Create object
obj = InterShear();

% Import ANSYS reference and measurement data
obj.DataImporter('test_ref_fullplate.txt', 'test_meas_fullplate.txt', 'de');

% Apply coordinate transformation
obj.transformCoordinates();

% Interpolate displacement field onto camera grid
obj.interpolateToCameraGrid();

% Suggest Gaussian sigma based on point density
obj.suggestSigmaByPointDensity();

% Apply Gaussian smoothing (manual sigma)
obj.applyGaussianSmoothing(5);

% Compute displacement gradients
obj.calculateStrainFlieds();

% Generate synthetic shearographic phase (shear_x, wavelength 635 nm, shear 5 mm)
obj.remodulatePhaseShift('shear_x', 635, 5);
```



