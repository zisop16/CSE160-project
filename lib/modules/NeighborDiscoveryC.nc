

configuration NeighborDiscoveryC {
    provides interface NeighborDiscovery;
}

implementation {
    components NeighborDiscovery;
    NeighborDiscovery = NeighborDiscoveryP.NeighborDiscovery;
}