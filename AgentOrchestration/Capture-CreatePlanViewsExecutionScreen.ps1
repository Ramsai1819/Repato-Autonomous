$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing,System.Windows.Forms
$path=Join-Path (Split-Path $PSScriptRoot -Parent) ('QA/Screenshots/cpv-71d2e887d7d741f5a085124ba26e152f-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'.png')
$bounds=[Windows.Forms.SystemInformation]::VirtualScreen
$bitmap=[Drawing.Bitmap]::new($bounds.Width,$bounds.Height);$graphics=[Drawing.Graphics]::FromImage($bitmap)
try{$graphics.CopyFromScreen($bounds.Left,$bounds.Top,0,0,$bounds.Size);$bitmap.Save($path,[Drawing.Imaging.ImageFormat]::Png);$path}finally{$graphics.Dispose();$bitmap.Dispose()}
