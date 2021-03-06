#include <metal_stdlib>
#import "ShaderTypes.h"

using namespace metal;

constant int MAX_ITERS = 10;  // adjust these higher for better/slower rendering
constant int MAX_STEPS = 150;

float DE    // distance estimate
(
 float3 position,
 constant Control &control)
{
    float3 c = control.isJulia ? control.julia : position;
    float3 v = position;
    float dr = 1.5;
    
    Control cc = control;
    
    for (int i = 0; i < MAX_ITERS; i++) {
        v = clamp(v, -cc.box.x, cc.box.x) * cc.box.y - v;
        if(control.isBurningShip) v = -abs(v);
        
        float mag = dot(v, v);
        if(mag < cc.sphere.x) {
            v = v * control.sphereMult;
            dr = dr * control.sphereMult;
        }
        else if (mag < cc.sphere.y) {
            v = v / mag;
            dr = dr / mag;
        }
        
        v = v * control.scaleFactor + c;
        dr = dr * abs(control.scaleFactor) + 1.0;

        cc.box *= cc.dBox;
        cc.sphere *= cc.dSphere;
        
        cc.dBox *= cc.ddBox;
        cc.dSphere *= cc.ddSphere;
    }
    
    return (length(v) - control.deFactor1) / dr - control.deFactor2;
}

//MARK: -

float3 getNormal
(
 float3 position,
 constant Control &control)
{
    float4 eps = float4(0, control.epsilon, 2.0 * control.epsilon, 3.0 * control.epsilon);
    return normalize(float3(-DE(position - eps.yxx,control) + DE(position + eps.yxx,control),
                            -DE(position - eps.xyx,control) + DE(position + eps.xyx,control),
                            -DE(position - eps.xxy,control) + DE(position + eps.xxy,control)));
}

//MARK: -

float3 lighting
(
 float3 position,
 float distance,
 constant Control &control)
{
    float3 normal = getNormal(position,control);
    float3 color = normal * control.color;
    
    float3 L = normalize(control.lighting.position - position);
    float dotLN = dot(L, normal);
    if(dotLN >= 0) {
        color += control.lighting.diffuse * dotLN;
        
        float3 V = normalize(float3(distance));
        float3 R = normalize(reflect(-L, normal));
        float dotRV = dot(R, V);
        if(dotRV >= 0) color += control.lighting.specular * pow(dotRV, 2);
    }
    
    return color;
}

//MARK: -

float3 rayMarch
(
 float3 rayDir,
 constant Control &control)
{
    float de,distance = 0.0;
    float3 position;
    float ff = pow(control.fog,4);

    for(int i = 0; i < MAX_STEPS; ++i) {
        position = control.camera + rayDir * distance;
        
        de = DE(position, control);
        if(de < control.epsilon) break;
        
        distance += de;
        if(distance > ff) return float3();
    }

    float3 color = lighting(position,distance,control);
    
    color *= (1 - distance / ff);
    return color;
}

//MARK: -

kernel void mandelBoxShader
(
 texture2d<float, access::write> outTexture [[texture(0)]],
 constant Control &control [[buffer(0)]],
 uint2 p [[thread_position_in_grid]])
{
    if(p.x > uint(control.xSize) || p.y > uint(control.ySize)) return;
    uint2 srcP = p;

    if(control.radialAngle > 0.01) { // 0 = don't apply
        float centerX = control.xSize/2;
        float centerY = control.ySize/2;
        float dx = float(p.x - centerX);
        float dy = float(p.y - centerY);
        
        float angle = fabs(atan2(dy,dx));
        
        float dRatio = 0.01 + control.radialAngle;
        while(angle > dRatio) angle -= dRatio;
        if(angle > dRatio/2) angle = dRatio - angle;
        
        float dist = sqrt(dx * dx + dy * dy);
        
        srcP.x = uint(centerX + cos(angle) * dist);
        srcP.y = uint(centerY + sin(angle) * dist);
    }

    float den = float(control.xSize);
    float dx =  control.zoom * (float(srcP.x)/den - 0.5);
    float dy = -control.zoom * (float(srcP.y)/den - 0.5);
    
    float3 direction = normalize((control.sideVector * dx) + (control.topVector * dy) + control.viewVector);
    
    outTexture.write(float4(rayMarch(direction,control),1),p);
}
