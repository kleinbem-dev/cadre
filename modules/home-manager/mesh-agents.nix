# Backward compatibility alias for services.cadre
{ packages }:
import ./cadre.nix { inherit packages; }
