    .inesprg 1   ; 1x 16KB PRG code
    .ineschr 1   ; 1x  8KB CHR data
    .inesmap 0   ; mapper 0 = NROM, no bank swapping
    .inesmir 1   ; background mirroring

    .rsset $0000    ; put variables starting at 0
direction .rs 1

    ; We use Bank 0 to hold our code and start it at location $C000
    .bank 0
    .org $C000

IncrementTileNumber:
    INC $0201
    RTS

DecrementTileNumber:
    DEC $0201
    RTS

SwitchRotationDirection:
    LDX #6
    CPX $0201
    BEQ SwitchDirectionBackwards

    LDX #0
    CPX $0201
    BEQ SwitchDirectionForwards

    RTS

SwitchDirectionBackwards
    LDA #0
    STA direction

    RTS

SwitchDirectionForwards
    LDA #1
    STA direction

    RTS

start:
    ; PALETTES
    ;
    ; Before putting any graphics on the screen, you first need to set the
    ; colour palette.
    ;
    ; There are two colour palettes, each 16 bytes. One is used for the
    ; background and one is used for sprites. The byte in the palette
    ; corresponds to one of the 64 base colours the NES can display. $0D is a
    ; bad color and should not be used (?)
    ;
    ; Palettes start at PPU address $3F00 and $3F10. To set this address, PPU
    ; address port $2006 is used. The port must be written twice, once for the
    ; high byte then for the low byte.
    ;
    ; This code tells the PPU to set its address to $3F10. Then the PPU data
    ; port at $2007 is ready to accept data. The first write will go to the
    ; address you set ($3F10), then the PPU will automatically increment the
    ; address after each read or write.
    ;
    ; Load palettes
    LDA $2002                     ; read PPU status to reset the high/low
                                  ; latch to high
    LDA #$3F
    STA $2006                     ; write the high byte of $3F10 address
    LDA #$00
    STA $2006                     ; write the low byte of $3F10 address

    ; Load the palette data
    LDX #0
LoadPalettesLoop:
    LDA PaletteData, x     ; load data from address (PaletteData + value in x)
    STA $2007              ; write to PPU
    INX                    ; inc x
    CPX #32                ; Compare x to 32
    BNE LoadPalettesLoop   ; (when (not= x 32) (recur))

    ; 256 x 240
    ;
    ; Sprites: each sprite needs the following 4 bytes of data:
    ;
    ; Y Position  | 7 = top, 223 = bottom
    ; Tile Number | 0 - 255
    ; Attributes  | 76543210
    ;               |||   ||
    ;               |||   ++- Color Palette of sprite. Choose which set of
    ;               |||       4 from the 16 colors to use.
    ;               |||
    ;               ||+------ Priority (0: in front of background;
    ;               ||                  1: behind background)
    ;               |+------- Flip sprite horizontally
    ;               +-------- Flip sprite vertically
    ; X Position  | 8 = left, 248 = right

    ; https://wiki.nesdev.com/w/index.php/PPU_OAM
    ; Sprite data is delayed by one scanline; you must subtract 1 from the
    ; sprite's Y coordinate, hence top left is 8x7.

    ; sprite 0 at 8x7
    LDA #7
    STA $0200 ; y pos
    LDA #0
    STA $0201 ; tile number
    STA $0202 ; attributes
    LDA #8
    STA $0203 ; x pos

    ; PPUCTRL ($2000)
    ;
    ;  76543210
    ;  | ||||||
    ;  | ||||++- Base nametable address
    ;  | ||||    (0 = $2000; 1 = $2400; 2 = $2800; 3 = $2C00)
    ;  | |||+--- VRAM address increment per CPU read/write of PPUDATA
    ;  | |||     (0: increment by 1, going across; 1: increment by 32, going
    ;  | |||     down)
    ;  | ||+---- Sprite pattern table address for 8x8 sprites (0: $0000;
    ;  | ||      1: $1000)
    ;  | |+----- Background pattern table address (0: $0000; 1: $1000)
    ;  | +------ Sprite size (0: 8x8; 1: 8x16)
    ;  |
    ;  +-------- Generate an NMI at the start of the
    ;            vertical blanking interval vblank (0: off; 1: on)
    ;
    ; enable NMI, sprites from pattern table 0
    LDA #%10000000
    STA $2000

    ; PPUMASK ($2001)
    ;
    ; 76543210
    ; ||||||||
    ; |||||||+- Grayscale (0: normal color; 1: AND all palette entries
    ; |||||||   with 0x30, effectively producing a monochrome display;
    ; |||||||   note that colour emphasis STILL works when this is on!)
    ; ||||||+-- Disable background clipping in leftmost 8 pixels of screen
    ; |||||+--- Disable sprite clipping in leftmost 8 pixels of screen
    ; ||||+---- Enable background rendering
    ; |||+----- Enable sprite rendering
    ; ||+------ Intensify reds (and darken other colors)
    ; |+------- Intensify greens (and darken other colors)
    ; +-------- Intensify blues (and darken other colors)
    ;
    ; enable sprites
    LDA #%00010000
    STA $2001

frame:
    ; SPRITE DMA
    ;
    ; The fastest and easiest way to transfer your sprites to memory is using
    ; DMA (Direct Memory Access). This just means a block of RAM is copied
    ; from CPU memory to the PPU sprite memory. The on-board RAM space from
    ; $0200-02FF is usually used for this purpose. To start the transfer, two
    ; bytes need to be written to the PPU ports. Like all graphics updates,
    ; this needs to be done at the beginning of the VBlank period, so it will
    ; go in the NMI section of the code:

    LDA #$00
    STA $2003                     ; set the low byte (00) of the RAM address
    LDA #$02
    STA $4014                     ; set the high byte (02) of the RAM address,
                                  ; start the transfer

    LDX #1
    CPX direction
    BEQ IncrementTileNumber
    BNE DecrementTileNumber

    JSR SwitchRotationDirection

    RTI

    .bank 1
    .org $E000

PaletteData:
    ; Background
    .db $0F,$31,$32,$33, $0F,$35,$36,$37, $0F,$39,$3A,$3B, $0F,$3D,$3E,$0F

    ; Sprite
    .db $2D,$1D,$21,$25, $0F,$02,$38,$3C, $0F,$1C,$15,$14, $0F,$02,$38,$3C

    .org $FFFA
    .dw  frame
    .dw  start

    ; Bank 2 starts at $0000 and contains our backgrounds and sprites.
    .bank 2
    .org 0
    .incbin "rotations.chr"
