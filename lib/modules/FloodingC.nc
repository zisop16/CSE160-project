configuration FloodingC {
    provides interface Flooding;
}

implementation {
    components FloodingP;
    components NeighborDiscoveryC;

    Flooding = FloodingP.Flooding;

    components new SimpleSendC(AM_PACK);

    FloodingP.Sender -> SimpleSendC;
    FloodingP.NeighborDiscovery -> NeighborDiscoveryC;
}