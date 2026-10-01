param([switch]$InstallStartup, [switch]$RemoveStartup)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$dataDir = Join-Path $env:LOCALAPPDATA 'WidgetDiscos'
[void][IO.Directory]::CreateDirectory($dataDir)
$stateFile = Join-Path $dataDir 'posicao.json'
$startupFile = Join-Path ([Environment]::GetFolderPath('Startup')) 'Widget Discos.lnk'
$powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if ($RemoveStartup) {
    Remove-Item -LiteralPath $startupFile -Force -ErrorAction SilentlyContinue
    [void][Windows.MessageBox]::Show('Inicializacao automatica desativada.', 'Widget Discos')
    exit
}
if ($InstallStartup) {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($startupFile)
    $shortcut.TargetPath = $powershellExe
    $shortcut.Arguments = '-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    $shortcut.WorkingDirectory = $PSScriptRoot
    $shortcut.Save()
    [void][Windows.MessageBox]::Show('O widget iniciara no proximo login. Mantenha esta pasta no mesmo local.', 'Widget Discos')
    exit
}
# Reopening Iniciar.cmd restores an already running, widget at full visibility.
$restoreEvent = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::AutoReset, 'Local\WidgetDiscosRestore')
$created = $false
$mutex = New-Object Threading.Mutex($true, 'Local\WidgetDiscosDesktop', [ref]$created)
if (-not $created) { [void]$restoreEvent.Set(); $restoreEvent.Dispose(); $mutex.Dispose(); exit }
try {
    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
 Title="Widget Discos" SizeToContent="WidthAndHeight" WindowStyle="None"
 ResizeMode="NoResize" AllowsTransparency="True" Background="Transparent"
 Topmost="True" ShowInTaskbar="False" FontFamily="Segoe UI">
 <Window.Resources>
  <SolidColorBrush x:Key="Surface" Color="#192230"/>
  <SolidColorBrush x:Key="Outline" Color="#364455"/>
  <SolidColorBrush x:Key="Muted" Color="#90A4BB"/>
  <SolidColorBrush x:Key="Close" Color="#C9D6E5"/>
  <SolidColorBrush x:Key="Check" Color="#BCCBDD"/>
  <SolidColorBrush x:Key="Card" Color="#263244"/>
  <SolidColorBrush x:Key="Title" Color="#D5E1EF"/>
  <SolidColorBrush x:Key="Detail" Color="#A7BAD0"/>
  <SolidColorBrush x:Key="Track" Color="#131C29"/>
  <SolidColorBrush x:Key="Healthy" Color="#4ADE80"/>
  <SolidColorBrush x:Key="Critical" Color="#FB7185"/>
  <SolidColorBrush x:Key="Warning" Color="#FBBF24"/>
  <SolidColorBrush x:Key="Text" Color="White"/>
 </Window.Resources>
 <Viewbox x:Name="FitBox" Stretch="Uniform" StretchDirection="DownOnly">
 <Border x:Name="ContentBorder" Width="280" Background="{DynamicResource Surface}" BorderBrush="{DynamicResource Outline}" BorderThickness="1" CornerRadius="12" Padding="12">
  <StackPanel>
   <Grid x:Name="Header" Background="Transparent" Margin="0,0,0,8" Cursor="SizeAll">
    <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
    <StackPanel><TextBlock Text="ARMAZENAMENTO" Foreground="{DynamicResource Muted}" FontSize="10"/>
     <TextBlock Text="Meus discos" Foreground="{DynamicResource Text}" FontWeight="SemiBold" FontSize="18"/></StackPanel>
    <Button x:Name="CloseButton" Grid.Column="1" Content="&#x00D7;" Width="24" Height="24"
     VerticalAlignment="Top" Background="Transparent" Foreground="{DynamicResource Close}" BorderThickness="0" FontSize="22" ToolTip="Fechar widget"/>
   </Grid>
   <UniformGrid x:Name="DrivesPanel" Columns="1"/>
   <Grid Margin="0,3,0,0">
    <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions>
    <RadioButton x:Name="SemiOption" GroupName="VisibilityMode" Content="Semitransparente"
     Foreground="{DynamicResource Check}" FontSize="11" ToolTip="50% de opacidade"/>
    <RadioButton x:Name="FullOption" Grid.Column="1" GroupName="VisibilityMode" Content="Totalmente visivel"
     Foreground="{DynamicResource Check}" FontSize="11" IsChecked="True" ToolTip="100% de opacidade"/>
   </Grid>
   <CheckBox x:Name="PinCheck" Content="Manter sobre as janelas" IsChecked="True" Foreground="{DynamicResource Check}" Margin="0,8,0,0" FontSize="11"/>
   <TextBlock x:Name="Updated" Foreground="{DynamicResource Muted}" FontSize="10" Margin="0,7,0,0"/>
  </StackPanel>
 </Border>
 </Viewbox>
</Window>
'@
    $reader = New-Object Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)
    $panel = $window.FindName('DrivesPanel')
    $fitBox = $window.FindName('FitBox')
    $contentBorder = $window.FindName('ContentBorder')
    function Fit-AllDrives([int]$count) {
        $area = [Windows.SystemParameters]::WorkArea
        $fitBox.MaxWidth = [Math]::Max(1, $area.Width - 24)
        $fitBox.MaxHeight = [Math]::Max(1, $area.Height - 24)
        $maxRows = [Math]::Max(1, [Math]::Floor(($area.Height - 160) / 110))
        $maxColumns = [Math]::Max(1, [Math]::Floor(($area.Width - 50) / 254))
        $columns = [Math]::Max(1, [Math]::Min($maxColumns, [Math]::Ceiling($count / $maxRows)))
        $panel.Columns = [int]$columns
        $contentBorder.Width = 26 + 254 * $columns
        if ($window.IsLoaded) {
            $window.UpdateLayout()
            $window.Left = [Math]::Max($area.Left, [Math]::Min($window.Left, $area.Right - $window.ActualWidth))
            $window.Top = [Math]::Max($area.Top, [Math]::Min($window.Top, $area.Bottom - $window.ActualHeight))
        }
    }
    $updated = $window.FindName('Updated')
    $pin = $window.FindName('PinCheck')
    $semiOption = $window.FindName('SemiOption')
    $fullOption = $window.FindName('FullOption')
    $script:lastUsage = @{}
    function Get-PanelOpacity {
        if ($semiOption.IsChecked -eq $true) { return 0.5 }
        return 1.0
    }
    function Set-PanelOpacity([bool]$Animate = $true) {
        $from = $window.Opacity
        $window.BeginAnimation([Windows.UIElement]::OpacityProperty, $null)
        $target = Get-PanelOpacity
        $window.Opacity = $target
        if ($Animate) {
            Animate-Value $window ([Windows.UIElement]::OpacityProperty) $from $target 220
        }
    }
    $semiOption.Add_Checked({ Set-PanelOpacity })
    $fullOption.Add_Checked({ Set-PanelOpacity })
    function Animate-Value($element, $property, [double]$from, [double]$to, [int]$milliseconds) {
        if (-not [Windows.SystemParameters]::ClientAreaAnimation -or [Math]::Abs($to - $from) -lt 0.01) { return }
        $animation = New-Object Windows.Media.Animation.DoubleAnimation
        $animation.From = $from
        $animation.To = $to
        $animation.Duration = [Windows.Duration]::new([TimeSpan]::FromMilliseconds($milliseconds))
        $easing = New-Object Windows.Media.Animation.CubicEase
        $easing.EasingMode = [Windows.Media.Animation.EasingMode]::EaseOut
        $animation.EasingFunction = $easing
        $animation.FillBehavior = [Windows.Media.Animation.FillBehavior]::Stop
        $element.BeginAnimation($property, $animation)
    }
    $window.FindName('CloseButton').Add_Click({ $window.Close() })
    $window.FindName('Header').Add_MouseLeftButtonDown({
        if ($_.OriginalSource -isnot [Windows.Controls.Button]) { $window.DragMove() }
    })
    $pin.Add_Checked({ $window.Topmost = $true })
    $pin.Add_Unchecked({ $window.Topmost = $false })
    function Format-Space([double]$bytes) {
        if ($bytes -ge 1TB) { return ('{0:N2} TiB' -f ($bytes / 1TB)) }
        return ('{0:N1} GiB' -f ($bytes / 1GB))
    }
    function Escape-Xml([string]$value) { return [Security.SecurityElement]::Escape($value) }
    function Update-Drives {
        try {
            $cards = New-Object 'Collections.Generic.List[object]'
            foreach ($drive in [IO.DriveInfo]::GetDrives()) {
                if ($drive.DriveType -notin @([IO.DriveType]::Fixed, [IO.DriveType]::Removable)) { continue }
                $name = $drive.Name.TrimEnd('\')
                try {
                    if (-not $drive.IsReady) { continue }
                    $total = [double]$drive.TotalSize
                    if ($total -le 0) { continue }
                    $free = [double]$drive.AvailableFreeSpace
                    $percent = [Math]::Max(0, [Math]::Min(100, 100 * $free / $total))
                    $used = 100 - $percent
                    $color = 'Healthy'
                    $status = 'Espaco disponivel'
                    if ($percent -lt 10) { $color = 'Critical'; $status = 'Espaco critico' }
                    elseif ($percent -lt 20) { $color = 'Warning'; $status = 'Pouco espaco' }
                    $label = $drive.VolumeLabel
                    if ([string]::IsNullOrWhiteSpace($label)) { $label = 'Disco' }
                    $title = Escape-Xml ($name + '  ' + $label)
                    $main = Escape-Xml ((Format-Space $free) + ' livres')
                    $detail = Escape-Xml ('de ' + (Format-Space $total) + ('  |  {0:N0}% livre' -f $percent))
                    $barValue = $used.ToString('F2', [Globalization.CultureInfo]::InvariantCulture)
                    [xml]$cardXml = @"
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Background="{DynamicResource Card}" CornerRadius="8" Height="104" Padding="10" Margin="0,0,6,6">
 <StackPanel>
  <TextBlock Text="$title" Foreground="{DynamicResource Title}" FontSize="11" TextTrimming="CharacterEllipsis" ToolTip="$title"/>
  <TextBlock Text="$main" Foreground="{DynamicResource Text}" FontWeight="SemiBold" FontSize="18" Margin="0,3,0,0"/>
  <TextBlock Text="$detail" Foreground="{DynamicResource Detail}" FontSize="11" Margin="0,2,0,6"/>
  <ProgressBar x:Name="UsageBar" Value="$barValue" Maximum="100" Height="5" Foreground="{DynamicResource $color}" Background="{DynamicResource Track}" BorderThickness="0" ToolTip="Percentual ocupado"/>
  <TextBlock Text="$status" Foreground="{DynamicResource $color}" FontSize="10" Margin="0,4,0,0"/>
 </StackPanel>
</Border>
"@
                    $cardReader = New-Object Xml.XmlNodeReader $cardXml
                    $card = [Windows.Markup.XamlReader]::Load($cardReader)
                    $cards.Add($card)
                    $bar = $card.FindName('UsageBar')
                    $previous = 0.0
                    if ($script:lastUsage.ContainsKey($name)) { $previous = [double]$script:lastUsage[$name] }
                    Animate-Value $bar ([Windows.Controls.Primitives.RangeBase]::ValueProperty) $previous $used 700
                    $script:lastUsage[$name] = $used
                } catch {
                    $notice = New-Object Windows.Controls.TextBlock
                    $notice.Text = $name + ' - indisponivel ou acesso negado'
                    $notice.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'Warning')
                    $notice.Margin = '0,0,0,10'
                    $cards.Add($notice)
                }
            }
            $panel.Children.Clear()
            foreach ($card in $cards) { [void]$panel.Children.Add($card) }
            if ($cards.Count -eq 0) {
                $empty = New-Object Windows.Controls.TextBlock
                $empty.Text = 'Nenhum disco local disponivel.'
                $empty.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'Text')
                [void]$panel.Children.Add($empty)
            }
            Fit-AllDrives $panel.Children.Count
            $updated.Text = 'Atualizado ' + (Get-Date -Format 'HH:mm:ss') + '  |  a cada 10 s'
        } catch { $updated.Text = 'Nao foi possivel atualizar. Tentando em 10 s.' }
    }
    $window.Add_ContentRendered({
        Fit-AllDrives $panel.Children.Count
        $area = [Windows.SystemParameters]::WorkArea
        $window.Left = $area.Right - $window.ActualWidth - 20
        $window.Top = $area.Top + 20
        if (Test-Path -LiteralPath $stateFile) {
            try {
                $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
                $window.Left = [Math]::Max($area.Left, [Math]::Min([double]$state.Left, $area.Right - $window.ActualWidth))
                $window.Top = [Math]::Max($area.Top, [Math]::Min([double]$state.Top, $area.Bottom - $window.ActualHeight))
                $pin.IsChecked = [bool]$state.Topmost
                if ($null -ne $state.PanelOpacity) {
                    # Migrate former slider values to the two supported modes.
                    if ([double]$state.PanelOpacity -lt 100) { $semiOption.IsChecked = $true }
                    else { $fullOption.IsChecked = $true }
                }
            } catch { }
        }
        Set-PanelOpacity -Animate $false
        Animate-Value $window ([Windows.UIElement]::OpacityProperty) 0 (Get-PanelOpacity) 350
    })
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(10)
    $timer.Add_Tick({ Update-Drives })
    $restoreTimer = New-Object Windows.Threading.DispatcherTimer
    $restoreTimer.Interval = [TimeSpan]::FromMilliseconds(250)
    $restoreTimer.Add_Tick({
        if ($restoreEvent.WaitOne(0)) {
            $fullOption.IsChecked = $true
            Set-PanelOpacity
            [void]$window.Activate()
        }
    })
    $window.Add_Closing({
        $timer.Stop()
        $restoreTimer.Stop()
        try {
            @{ Left = $window.Left; Top = $window.Top; Topmost = $window.Topmost; PanelOpacity = ((Get-PanelOpacity) * 100) } |
                ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding UTF8
        } catch { }
    })
    Update-Drives
    $timer.Start()
    $restoreTimer.Start()
    [void]$window.ShowDialog()
} catch {
    $_ | Out-String | Set-Content -LiteralPath (Join-Path $dataDir 'erro.txt') -Encoding UTF8
    [void][Windows.MessageBox]::Show('Nao foi possivel abrir o widget. Detalhes em ' + $dataDir + '\erro.txt', 'Widget Discos')
} finally {
    if ($null -ne $restoreTimer) { $restoreTimer.Stop() }
    if ($null -ne $timer) { $timer.Stop() }
    $restoreEvent.Dispose()
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
