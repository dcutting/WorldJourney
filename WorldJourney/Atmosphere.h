#ifndef Atmosphere_h
#define Atmosphere_h

float3 calculate_scattering(
    float3 start,                 // the start of the ray (the camera position)
    float3 dir,                     // the direction of the ray (the camera vector)
    float max_dist,             // the maximum distance the ray can travel (because something is in the way, like an object)
    float3 scene_color,            // the color of the scene
    float3 light_dir,             // the direction of the light
    float3 light_intensity,        // how bright the light is, affects the brightness of the atmosphere
    float3 planet_position,         // the position of the planet
    float planet_radius,         // the radius of the planet
    float atmo_radius,             // the radius of the atmosphere
    float3 beta_ray,                 // the amount rayleigh scattering scatters the colors (for earth: causes the blue atmosphere)
    float3 beta_mie,                 // the amount mie scattering scatters colors
    float3 beta_absorption,       // how much air is absorbed
    float3 beta_ambient,            // the amount of scattering that always occurs, cna help make the back side of the atmosphere a bit brighter
    float g,                     // the direction mie scatters the light in (like a cone). closer to -1 means more towards a single direction
    float height_ray,             // how high do you have to go before there is no rayleigh scattering?
    float height_mie,             // the same, but for mie
    float height_absorption,    // the height at which the most absorption happens
    float absorption_falloff,    // how fast the absorption falls off from the absorption height
    int steps_i,                 // the amount of steps along the 'primary' ray, more looks better but slower
    int steps_l                 // the amount of steps along the light ray, more looks better but slower
);

#endif /* Atmosphere_h */



//// first, lets define some constants to use (planet radius, position, and scattering coefficients)
//#define PLANET_POS float3(0.0, -5000, 0) /* the position of the planet */
//#define PLANET_RADIUS 5000//6371e3 /* radius of the planet */
//#define ATMOS_RADIUS 10000//6471e3 /* radius of the atmosphere */
//// scattering coeffs
//#define RAY_BETA float3(5.5e-6, 13.0e-6, 22.4e-6) /* rayleigh, affects the color of the sky */
//#define MIE_BETA float3(21e-6) /* mie, affects the color of the blob around the sun */
//#define AMBIENT_BETA float3(0.0) /* ambient, affects the scattering color when there is no lighting from the sun */
//#define ABSORPTION_BETA float3(2.04e-5, 4.97e-5, 1.95e-6) /* what color gets absorbed by the atmosphere (Due to things like ozone) */
//#define G 0.7 /* mie scattering direction, or how big the blob around the sun is */
//// and the heights (how far to go up before the scattering has no effect)
//#define HEIGHT_RAY 6000 /* rayleigh height */
//#define HEIGHT_MIE 4000 /* and mie */
//#define HEIGHT_ABSORPTION 2000 /* at what height the absorption is at it's maximum */
//#define ABSORPTION_FALLOFF 100 /* how much the absorption decreases the further away it gets from the maximum height */
//// and the steps (more looks better, but is slower)
//// the primary step has the most effect on looks
//#define PRIMARY_STEPS 64 /* primary steps, affects quality the most */
//#define LIGHT_STEPS 4 /* light steps, how much steps in the light direction are taken */
//
////constant bool atmospheric_scattering = false;


//  if (atmospheric_scattering) {
//
//    float4 scene = float4(scene_color, TERRAIN_SIZE);  // TODO: should get w from depthMap
//
//    float3 camera_position = uniforms.cameraPosition;
//
//    // get the scene color and depth, color is in xyz, depth in w
//    // replace this with something better if you are using this shader for something else
//
//    // the color of this pixel
//    float3 col = float3(0.0);
//
//    // get the atmosphere color
//    col += calculate_scattering(
//                                camera_position,                // the position of the camera
//                                cameraDirection,                     // the camera vector (ray direction of this pixel)
//                                scene.w,                         // max dist, essentially the scene depth
//                                scene.xyz,                        // scene color, the color of the current pixel being rendered
//                                light_dir,                        // light direction
//                                float3(1.0),                        // light intensity, 40 looks nice
//                                PLANET_POS,                        // position of the planet
//                                PLANET_RADIUS,                  // radius of the planet in meters
//                                ATMOS_RADIUS,                   // radius of the atmosphere in meters
//                                RAY_BETA,                        // Rayleigh scattering coefficient
//                                MIE_BETA,                       // Mie scattering coefficient
//                                ABSORPTION_BETA,                // Absorbtion coefficient
//                                AMBIENT_BETA,                    // ambient scattering, turned off for now. This causes the air to glow a bit when no light reaches it
//                                G,                              // Mie preferred scattering direction
//                                HEIGHT_RAY,                     // Rayleigh scale height
//                                HEIGHT_MIE,                     // Mie scale height
//                                HEIGHT_ABSORPTION,                // the height at which the most absorption happens
//                                ABSORPTION_FALLOFF,                // how fast the absorption falls off from the absorption height
//                                PRIMARY_STEPS,                     // steps in the ray direction
//                                LIGHT_STEPS                     // steps in the light direction
//                                );
//
//    // apply exposure, removing this makes the brighter colors look ugly
//    // you can play around with removing this
//    col = 1.0 - exp(-col);
//
//
//    // Output to screen
//    scene_color = col;
//  }

