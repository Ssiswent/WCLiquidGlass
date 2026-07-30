#include <stdlib.h>

__attribute__((constructor(101)))
static void WCLiquidGlassBootstrapSystemGlass(void) {
    setenv("UIDesignSwiftUIDesignIgnoreCheck", "1", 1);
    setenv("UIDesignSwiftUIDesignEnableGlass", "1", 1);
}
