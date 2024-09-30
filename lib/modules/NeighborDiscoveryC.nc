configuration NeighborDiscoveryC {
    provides interface NeighborDiscovery;
}

implementation {
    components NeighborDiscoveryP;
    NeighborDiscovery = NeighborDiscoveryP.NeighborDiscovery;

    components new TimerMilliC() as discoveryTimer;
    components new SimpleSendC(AM_PACK);

    NeighborDiscoveryP.discoveryTimer -> discoveryTimer;
    NeighborDiscoveryP.Sender -> SimpleSendC;
}