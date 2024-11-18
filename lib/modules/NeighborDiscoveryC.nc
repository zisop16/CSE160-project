configuration NeighborDiscoveryC {
    provides interface NeighborDiscovery;
}

implementation {
    components NeighborDiscoveryP;
    components LinkStateC;
    NeighborDiscovery = NeighborDiscoveryP.NeighborDiscovery;

    components new TimerMilliC() as discoveryTimer;
    components new SimpleSendC(AM_PACK);

    NeighborDiscoveryP.LinkState -> LinkStateC;
    NeighborDiscoveryP.discoveryTimer -> discoveryTimer;
    NeighborDiscoveryP.Sender -> SimpleSendC;
}