configuration FloodingC {
    provides interface Flooding;
}

implementation {
    components Flooding;
    Flooding = FloodingP.Flooding;
}