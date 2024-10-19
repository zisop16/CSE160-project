configuration FloodingC {
    provides interface Flooding;
}

implementation {
    components FloodingP;
    components NeighborDiscoveryC;
    components LinkStateC;

    Flooding = FloodingP.Flooding;

    components new SimpleSendC(AM_PACK);
    components new TimerMilliC() as acknowledgementTimer;

    FloodingP.Sender -> SimpleSendC;
    FloodingP.NeighborDiscovery -> NeighborDiscoveryC;
    FloodingP.LinkState -> LinkStateC;
    FloodingP.acknowledgementTimer -> acknowledgementTimer;
}