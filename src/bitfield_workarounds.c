#include "bitfield_workarounds.h"

#include <gui.h>

void PFUI_updateMouseButtonsFields(bool left, bool middle, bool right, bool extra1, bool extra2)
{
  PFUI_updateMouseButtons((PFUI_MouseButtons){left, middle, right, extra1, extra2});
}
