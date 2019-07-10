# Panorama180Movement Demo

[Japanese readme](./README_jp.md)

## In the beginning

When using a 180 degree panorama-3D image such as the VR 180, the player can turn around the camera on the VR but can not move it.     
This is 3DoF operation.    
It is possible to move in a specific direction on the VR space using this panoramic image,    
perform calculations with as little load as possible, and enable limited 6DoF operation.    

![img_00](images/unity_panorama180Movement_movie.gif)     

## Operation check environment

Unity 2019.1.9f1 (Windows)    
Unity 2019.1.1f1 (Windows)    
Unity 2018.3.8 (Windows)    

## Development environment

Unity 2018.3.8 (Windows)     

## How to use

Open the [Panorama180Movement] folder in Unity, and then open the Scene/SampleScene scene.    
Specify the information of "Spatial cache" (RGB texture, depth texture, movement coordinate, Y rotation value, etc.) stored as a resource in Main Camera in advance.    
Note that implementations such as resource loading are hard-coded.    
Please use this as a demonstration to the last.    

The run was confirmed using the Oculus Rift.    

## Executable file

Download the executable file from the following.    

https://ft-lab.jp/VRTest/index.html

## Algorithm explanation

The following describes the algorithm of this demo.    

https://ft-lab.jp/VRTest/algorithm.html

## Change log

### [04/30/2019]

- README updated. Added English README.

### [04/29/2019]

- Upload source code to GitHub

### [04/23/2019] ver.1.0.1    

- Optimize internal resources (capacity reduction)
- Optimization of spatial interpolation processing

### [04/14/2019] ver.1.0.0

- First release
