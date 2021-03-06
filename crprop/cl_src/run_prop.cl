

#include <constants.cl>
#include <utils.cl>
#include <vector_funcs.cl>
#include <particle_props.cl>
#include <bfield.cl>



// Propagation Step function
static void Propagate(float time_step, 
                      struct particle_struct *particle, 
                      float4 startp, float4 startv, 
                      struct igrf_struct *coeff_struct)
{

    float life = vec_three_Mag(particle->pos);

    // If particle hits Earth or get too far away, respawn
    //bool death = (life<=E_r_m || life>60.f*E_r_m);
    bool death = (life<=E_r_m || life>10.f*E_r_m);
    if (death)
    {
        float speed = vec_three_Mag(particle->vel);
        particle->pos = 1e10;//vec_scale(E_r_m,startp);
        particle->vel = 0;//vec_scale(speed,startv);
        life = vec_three_Mag(startp); 
    }

    //PropStepRK4(time_step,particle);
    //PropStepLin(time_step,particle);

    PropStepBoris(time_step,particle,coeff_struct);
    //PropStepAdaptBoris(time_step,particle,coeff_struct);
}


// Main kernel function
__kernel void particle_prop(__global float4* position, 
                            __global float4* color,
                            __global float4* velocity,
                            __global float4* zmel,
                            __global float4* start_position,
                            __global float4* start_velocity,
                            float maxE,
                            float range,
                            float time_step)
{
    // Get this particles address on GPU
    unsigned int gid = get_global_id(0);

    // Grab position and direction vectors
    float4 p = vec_scale(E_r_m,position[gid]);
    float4 v = velocity[gid];

    // Scale dir vector to speed
    float gamma = zmel[gid].w;
    float speed = sqrt(1.-1./(gamma*gamma))*speed_of_light;
    v = vec_normalize(v);
    v = vec_scale(speed,v);

    // Put gid particle's properties in struct
    struct particle_struct particle;
    particle.pos = p;
    particle.vel = v;
    particle.ZMEL = zmel[gid];
    particle.alive = true;
    particle.time = velocity[gid].w;

    // Allocate igrf coefficients with current days since 2000
    struct igrf_struct coeff_struct;
    coeff_struct.days = 0.f;
    SetCoeffIndexScheme(&coeff_struct);

    // Propagate in time via stepper function of choice
    Propagate(time_step, &particle, start_position[gid], start_velocity[gid], &coeff_struct);

    // Grab position and velocity, ensuring to scale properly for viewing
    p = particle.pos;
    p = vec_scale(1./E_r_m,p);
    p.w = 1.;
    position[gid] = p;

    v = particle.vel;
    v.w = particle.time;
    velocity[gid] = v;
    
    zmel[gid].w = particle.ZMEL.w;
    
    float energy = log10(particle.ZMEL.z);
    float lambda = (780.-380.)*(maxE-energy)/range+380.;
    if (range == 0.)
        lambda = 580.;
    color[gid] = Colors(lambda);
    color[gid].w = 1.0f; /* Fade points as life decreases */
}
