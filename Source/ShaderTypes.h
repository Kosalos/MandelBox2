#pragma once

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NSInteger metal::int32_t
#else
#import <Foundation/Foundation.h>
#endif

#include <simd/simd.h>

typedef struct {
    matrix_float4x4 transformMatrix;
    matrix_float3x3 endPosition;
} ArcBallData;

typedef struct {
    vector_float3 position;
    float diffuse;
    float specular;
    float saturation;
    float gamma;
} Lighting;

typedef struct {
    int version;
    vector_float3 camera;
    vector_float3 focus;

    int xSize,ySize;
    float zoom;
    float scaleFactor;
    float epsilon;
    
    ArcBallData aData;
    
    vector_float3 julia;
    bool isJulia;
    
    vector_float3 sphere;
    float sphereMult;
    vector_float3 box;
    vector_float3 color;

    Lighting lighting;

    vector_float3 viewVector,topVector,sideVector;

    float parallax;
    bool isBurningShip;
    float fog;
    
    float deFactor1,deFactor2;
}  Control;

//MARK: -

#define MAX_ENTRY 100

typedef struct{
    vector_float3 camera;
    vector_float3 focus;
    float parallax;
    ArcBallData aData;
} RecordEntry;

typedef struct{
    int version;
    Control memory;
    int count;
    RecordEntry entry[MAX_ENTRY];
} RecordStruct;

#ifndef __METAL_VERSION__

extern ArcBallData aData;

void setRecordPointer(RecordStruct *rPtr,Control *cPtr);
void saveControlMemory(void);
void restoreControlMemory(void);
void saveRecordStructEntry(void);
RecordEntry getRecordStructEntry(int index);

#endif

