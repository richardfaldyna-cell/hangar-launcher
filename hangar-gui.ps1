<#
.SYNOPSIS
    Hangar — graphical front end: a window with the project list, search and a
    detail panel.

.DESCRIPTION
    Presentation layer on top of hangar-core.ps1. Index, search, frecency and
    launching are shared with the terminal picker (hangar.ps1) — this file only draws.

    WPF via Add-Type -AssemblyName PresentationFramework; no build step, no MSIX.
    The XAML is loaded with XamlReader, so it must not contain x:Class and elements
    are reached through FindName.

    Keys:
      typing          filter (focus always stays in the search box)
      arrows          selection, even while typing
      Enter           claude in a new tab
      Shift+Enter     claude in a new window
      Ctrl+Enter      claude --continue
      Ctrl+S          plain shell
      Ctrl+E          VS Code
      Ctrl+O          Explorer
      F5              refresh the index
      Esc             close

.EXAMPLE
    ./hangar-gui.ps1
    hangar -Gui
#>
[CmdletBinding()]
param(
    # Pre-filled filter — the window opens already filtered (hangar ng -Gui).
    [string]$Project,
    # Force a fresh index before starting.
    [switch]$Refresh,
    # Only print what would be launched.
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'hangar-core.ps1')

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

Import-HangarIndex -Refresh:$Refresh

# --- palette --------------------------------------------------------------------------
# Follows the tab colours (business #C0392B, private #1A6FB5), only lightened so they
# keep their contrast on the dark background.
$Brush = @{}
$brushConverter = [System.Windows.Media.BrushConverter]::new()
foreach ($pair in @{
    business = '#E8705F'
    private  = '#58A6FF'
    root     = '#8B98A5'
    dirty    = '#E3B341'
    ahead    = '#3FB950'
    behind   = '#E8705F'
    todos    = '#D29922'
    worktree = '#BC8CFF'
    muted    = '#8B98A5'
}.GetEnumerator()) {
    $Brush[$pair.Key] = $brushConverter.ConvertFromString($pair.Value)
    $Brush[$pair.Key].Freeze()
}

# --- XAML -----------------------------------------------------------------------------
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Hangar" Height="660" Width="1020" MinHeight="480" MinWidth="860"
        WindowStartupLocation="CenterScreen" Background="#0D1117"
        TextOptions.TextFormattingMode="Display"
        FontFamily="Segoe UI" FontSize="13">

  <Window.Resources>
    <SolidColorBrush x:Key="Bg"      Color="#0D1117"/>
    <SolidColorBrush x:Key="Panel"   Color="#131920"/>
    <SolidColorBrush x:Key="Border"  Color="#242C37"/>
    <SolidColorBrush x:Key="Text"    Color="#E6EDF3"/>
    <SolidColorBrush x:Key="Muted"   Color="#8B98A5"/>
    <SolidColorBrush x:Key="Dim"     Color="#5C6773"/>
    <SolidColorBrush x:Key="Sel"     Color="#1F2937"/>
    <SolidColorBrush x:Key="Hover"   Color="#181F28"/>

    <!-- List row. Without its own style a ListBoxItem gets the system blue
         selection, which clashes with the dark background. -->
    <Style x:Key="RowStyle" TargetType="ListBoxItem">
      <Setter Property="Padding" Value="14,9"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListBoxItem">
            <Border x:Name="Bd" Background="{TemplateBinding Background}"
                    CornerRadius="6" Padding="{TemplateBinding Padding}"
                    Margin="6,1,6,1">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{StaticResource Hover}"/>
              </Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{StaticResource Sel}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="DetailLabel" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{StaticResource Dim}"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="Margin" Value="0,10,0,2"/>
    </Style>
    <Style x:Key="DetailValue" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{StaticResource Text}"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
    </Style>
  </Window.Resources>

  <Grid Margin="0">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- search -->
    <Border Grid.Row="0" Background="{StaticResource Panel}" BorderBrush="{StaticResource Border}"
            BorderThickness="0,0,0,1" Padding="18,14">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBox x:Name="SearchBox" Grid.Column="0" Background="Transparent"
                 Foreground="{StaticResource Text}" CaretBrush="{StaticResource Text}"
                 BorderThickness="0" FontSize="20" Padding="0"
                 VerticalContentAlignment="Center"/>
        <TextBlock x:Name="Placeholder" Grid.Column="0" Text="Search projects…"
                   Foreground="{StaticResource Dim}" FontSize="20"
                   IsHitTestVisible="False" VerticalAlignment="Center"/>
        <TextBlock x:Name="CountLabel" Grid.Column="1" Foreground="{StaticResource Dim}"
                   VerticalAlignment="Center" Margin="16,0,0,0"/>
      </Grid>
    </Border>

    <!-- list + detail -->
    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="1.45*" MinWidth="380"/>
        <ColumnDefinition Width="Auto"/>
        <ColumnDefinition Width="1*" MinWidth="260"/>
      </Grid.ColumnDefinitions>

      <ListBox x:Name="ProjectList" Grid.Column="0" Background="Transparent"
               BorderThickness="0" Padding="0,8"
               ItemContainerStyle="{StaticResource RowStyle}"
               ScrollViewer.HorizontalScrollBarVisibility="Disabled"
               VirtualizingPanel.IsVirtualizing="True">
        <ListBox.ItemTemplate>
          <DataTemplate>
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
              </Grid.RowDefinitions>

              <!-- group dot -->
              <Ellipse Grid.Column="0" Grid.RowSpan="2" Width="7" Height="7"
                       Fill="{Binding GroupBrush}" VerticalAlignment="Center"
                       Margin="0,0,11,0"/>

              <TextBlock Grid.Column="1" Grid.Row="0" Text="{Binding Name}"
                         Foreground="#E6EDF3" FontSize="14" FontWeight="SemiBold"
                         TextTrimming="CharacterEllipsis"/>
              <TextBlock Grid.Column="1" Grid.Row="1" Text="{Binding Path}"
                         Foreground="#7D8894" FontSize="11.5"
                         FontFamily="Cascadia Mono, Consolas"
                         TextTrimming="CharacterEllipsis" Margin="0,1,0,0"/>

              <TextBlock Grid.Column="2" Grid.Row="0" Text="{Binding Age}"
                         Foreground="#5C6773" FontSize="11.5"
                         HorizontalAlignment="Right" Margin="10,0,0,0"/>
              <!-- Segoe UI Symbol, not the inherited Segoe UI: neither ☐ (U+2610) nor
                   ⇡⇣ (U+21E1/21E3) is in plain Segoe UI and they rendered as empty boxes.
                   The terminal did not mind — Cascadia Mono has those glyphs. -->
              <StackPanel Grid.Column="2" Grid.Row="1" Orientation="Horizontal"
                          HorizontalAlignment="Right" Margin="10,1,0,0"
                          TextElement.FontFamily="Segoe UI Symbol, Segoe UI">
                <TextBlock Text="{Binding Dirty}"    Foreground="{Binding DirtyBrush}"    FontSize="11.5"/>
                <TextBlock Text="{Binding Ahead}"    Foreground="{Binding AheadBrush}"    FontSize="11.5"/>
                <TextBlock Text="{Binding Behind}"   Foreground="{Binding BehindBrush}"   FontSize="11.5"/>
                <TextBlock Text="{Binding Todos}"    Foreground="{Binding TodosBrush}"    FontSize="11.5"/>
                <TextBlock Text="{Binding Worktree}" Foreground="{Binding WorktreeBrush}" FontSize="11.5"/>
              </StackPanel>
            </Grid>
          </DataTemplate>
        </ListBox.ItemTemplate>

        <ListBox.GroupStyle>
          <GroupStyle>
            <GroupStyle.HeaderTemplate>
              <DataTemplate>
                <TextBlock Text="{Binding Name}" Foreground="#5C6773" FontSize="10.5"
                           FontWeight="SemiBold" Margin="20,14,0,4"/>
              </DataTemplate>
            </GroupStyle.HeaderTemplate>
          </GroupStyle>
        </ListBox.GroupStyle>
      </ListBox>

      <Border Grid.Column="1" Width="1" Background="{StaticResource Border}"/>

      <ScrollViewer Grid.Column="2" VerticalScrollBarVisibility="Auto"
                    Background="{StaticResource Panel}">
        <StackPanel x:Name="Detail" Margin="20,18,20,20">
          <TextBlock x:Name="DName" Foreground="{StaticResource Text}" FontSize="17"
                     FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/>
          <TextBlock x:Name="DPath" Foreground="{StaticResource Muted}" FontSize="11.5"
                     FontFamily="Cascadia Mono, Consolas" TextWrapping="Wrap" Margin="0,3,0,0"/>

          <TextBlock Text="STATUS" Style="{StaticResource DetailLabel}" Margin="0,18,0,4"/>
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="Auto" MinWidth="86"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <TextBlock Grid.Row="0" Grid.Column="0" Text="Branch"       Foreground="{StaticResource Dim}" Margin="0,0,14,0"/>
            <TextBlock Grid.Row="1" Grid.Column="0" Text="Changes"      Foreground="{StaticResource Dim}" Margin="0,0,14,0"/>
            <TextBlock Grid.Row="2" Grid.Column="0" Text="Ahead/behind" Foreground="{StaticResource Dim}" Margin="0,0,14,0"/>
            <TextBlock Grid.Row="3" Grid.Column="0" Text="Tasks"        Foreground="{StaticResource Dim}" Margin="0,0,14,0"/>
            <TextBlock Grid.Row="4" Grid.Column="0" Text="Worktrees"    Foreground="{StaticResource Dim}" Margin="0,0,14,0"/>
            <TextBlock x:Name="DBranch"    Grid.Row="0" Grid.Column="1" Style="{StaticResource DetailValue}"/>
            <TextBlock x:Name="DDirty"     Grid.Row="1" Grid.Column="1" Style="{StaticResource DetailValue}"/>
            <TextBlock x:Name="DSync"      Grid.Row="2" Grid.Column="1" Style="{StaticResource DetailValue}"/>
            <TextBlock x:Name="DTodos"     Grid.Row="3" Grid.Column="1" Style="{StaticResource DetailValue}"/>
            <TextBlock x:Name="DWorktrees" Grid.Row="4" Grid.Column="1" Style="{StaticResource DetailValue}"/>
          </Grid>

          <TextBlock Text="LAST COMMIT" Style="{StaticResource DetailLabel}" Margin="0,20,0,4"/>
          <TextBlock x:Name="DCommitMeta" Foreground="{StaticResource Muted}" FontSize="11.5"
                     FontFamily="Cascadia Mono, Consolas"/>
          <TextBlock x:Name="DCommitSubject" Style="{StaticResource DetailValue}" Margin="0,3,0,0"/>

          <TextBlock Text="CLAUDE SESSIONS" Style="{StaticResource DetailLabel}" Margin="0,20,0,4"/>
          <TextBlock x:Name="DSessions" Style="{StaticResource DetailValue}"/>
        </StackPanel>
      </ScrollViewer>
    </Grid>

    <!-- key hints -->
    <Border Grid.Row="2" Background="{StaticResource Panel}" BorderBrush="{StaticResource Border}"
            BorderThickness="0,1,0,0" Padding="18,9">
      <TextBlock x:Name="HintLabel" Foreground="{StaticResource Dim}" FontSize="11.5"
                 TextTrimming="CharacterEllipsis"/>
    </Border>
  </Grid>
</Window>
'@

$window = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new([xml]$xaml))

# Dark title bar. WPF does not paint it — DWM does, and without this attribute it stays
# light above a dark window. Attribute 20 = DWMWA_USE_IMMERSIVE_DARK_MODE; it can only
# be set once the window has a handle, i.e. in SourceInitialized.
if (-not ('HangarDwm' -as [type])) {
    Add-Type -Namespace '' -Name 'HangarDwm' -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("dwmapi.dll")]
public static extern int DwmSetWindowAttribute(System.IntPtr hwnd, int attr, ref int value, int size);
'@
}
$window.Add_SourceInitialized({
    $handle = [System.Windows.Interop.WindowInteropHelper]::new($window).Handle
    $enabled = 1
    # Older Windows 10 builds do not know the attribute and return an error code — the
    # title bar stays light and nothing else happens, so the return value is ignored.
    [HangarDwm]::DwmSetWindowAttribute($handle, 20, [ref]$enabled, 4) | Out-Null
})

$searchBox   = $window.FindName('SearchBox')
$placeholder = $window.FindName('Placeholder')
$countLabel  = $window.FindName('CountLabel')
$list        = $window.FindName('ProjectList')
$hint        = $window.FindName('HintLabel')

$detail = @{}
foreach ($name in 'DName','DPath','DBranch','DDirty','DSync','DTodos','DWorktrees',
                  'DCommitMeta','DCommitSubject','DSessions') {
    $detail[$name] = $window.FindName($name)
}

$hint.Text = 'Enter tab  ·  Shift+Enter new window  ·  Ctrl+Enter resume  ·  ' +
             'Ctrl+S shell  ·  Ctrl+E VS Code  ·  Ctrl+O Explorer  ·  F5 refresh  ·  Esc'

# --- list items -----------------------------------------------------------------------

function New-ListItem($p, [string]$Section) {
    # Badges carry their own spacing, so an empty badge takes up exactly zero pixels.
    # With a Margin every missing value would leave a gap and the right column would jump.
    $dirty = ''; $ahead = ''; $behind = ''
    if ($p.git) {
        if ($p.git.dirty  -gt 0) { $dirty  = "~$($p.git.dirty)   " }
        if ($p.git.ahead  -gt 0) { $ahead  = "⇡$($p.git.ahead)   " }
        if ($p.git.behind -gt 0) { $behind = "⇣$($p.git.behind)   " }
    }
    [pscustomobject]@{
        Ref           = $p
        Section       = $Section
        Name          = $p.name
        # The workspace root has id "." — a bare dot says nothing as a subtitle.
        Path          = if ($p.id -eq '.') { 'workspace root' } else { $p.id }
        Age           = Format-Age $p.claude.lastSessionAt
        Dirty         = $dirty
        Ahead         = $ahead
        Behind        = $behind
        Todos         = if ($p.openTodos -gt 0)       { "☐$($p.openTodos)   " }        else { '' }
        Worktree      = if ($p.worktrees.Count -gt 0) { "wt:$($p.worktrees.Count)" } else { '' }
        GroupBrush    = $Brush[$p.group]
        DirtyBrush    = $Brush.dirty
        AheadBrush    = $Brush.ahead
        BehindBrush   = $Brush.behind
        TodosBrush    = $Brush.todos
        WorktreeBrush = $Brush.worktree
    }
}

$SectionLabel = @{ business = 'BUSINESS'; private = 'PRIVATE'; root = 'OTHER' }
# How many projects the "Recent" section at the top holds. Five is about right: it
# covers a normal week of work and still fits above the fold, so the rest of the list
# keeps its weight.
$RecentCount = 5

function Update-List {
    $query = $searchBox.Text
    $found = @(Find-Project $query)

    $items = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    if ($query) {
        # No grouping while searching: the best match must be the first row, and section
        # headers would chop the relevance order into pieces.
        foreach ($p in $found) { $items.Add((New-ListItem $p '')) }
    } else {
        $recent = @($found | Select-Object -First $RecentCount)
        foreach ($p in $recent) { $items.Add((New-ListItem $p 'RECENT')) }
        $rest = @($found | Select-Object -Skip $RecentCount)
        foreach ($group in 'business', 'private', 'root') {
            foreach ($p in @($rest | Where-Object { $_.group -eq $group })) {
                $items.Add((New-ListItem $p $SectionLabel[$group]))
            }
        }
    }

    $list.ItemsSource = $items
    $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($items)
    $view.GroupDescriptions.Clear()
    if (-not $query) {
        $view.GroupDescriptions.Add([System.Windows.Data.PropertyGroupDescription]::new('Section'))
    }

    $countLabel.Text = if ($query) { "$($items.Count) of $((Get-HangarProjects).Count)" }
                       else        { "$($items.Count) projects" }
    $placeholder.Visibility = if ($query) { 'Collapsed' } else { 'Visible' }
    if ($items.Count -gt 0) { $list.SelectedIndex = 0 }
    else { Update-Detail $null }
}

# --- detail panel ---------------------------------------------------------------------

function Update-Detail($item) {
    if (-not $item) {
        $detail.DName.Text = 'Nothing found'
        $detail.DPath.Text = ''
        foreach ($k in 'DBranch','DDirty','DSync','DTodos','DWorktrees',
                       'DCommitMeta','DCommitSubject','DSessions') { $detail[$k].Text = '' }
        return
    }

    $p = $item.Ref
    $detail.DName.Text = $p.name
    $detail.DPath.Text = (Get-ProjectPath $p)

    if ($p.git) {
        $detail.DBranch.Text = $p.git.branch
        $detail.DDirty.Text  = if ($p.git.dirty -gt 0) { "$($p.git.dirty) files" } else { 'clean' }
        $detail.DSync.Text   = if ($p.git.ahead -eq 0 -and $p.git.behind -eq 0) { 'in sync' }
                               else { "⇡$($p.git.ahead)  ⇣$($p.git.behind)" }
        # Built only from what exists — TrimStart used to leave "4d4c7d6  ·   ago"
        # dangling with an empty age when the commit had no date.
        $meta = @()
        if ($p.git.lastCommitShort) { $meta += $p.git.lastCommitShort }
        $age = Format-Age $p.git.lastCommit
        if ($age) { $meta += "$age ago" }
        $detail.DCommitMeta.Text    = $meta -join '  ·  '
        $detail.DCommitSubject.Text = $p.git.lastCommitSubject
    } else {
        # A project without .git — only CLAUDE.md. Not an error, just a smaller project.
        $detail.DBranch.Text = '— not a git repository'
        foreach ($k in 'DDirty','DSync','DCommitMeta','DCommitSubject') { $detail[$k].Text = '' }
    }

    $detail.DTodos.Text = if ($p.openTodos -gt 0) { "$($p.openTodos) open" } else { '—' }
    $detail.DWorktrees.Text = if ($p.worktrees.Count -gt 0) { $p.worktrees -join ', ' } else { '—' }

    # Past sessions are visible here instead of having to be guessed from the list.
    $detail.DSessions.Text = if ($p.claude) {
        $sessionCount = if ($p.claude.sessionCount) { $p.claude.sessionCount } else { 1 }
        "$sessionCount · last one $(Format-Age $p.claude.lastSessionAt) ago"
    } else { 'no terminal session' }
}

# --- actions --------------------------------------------------------------------------

function Invoke-Action([string]$Action) {
    $item = $list.SelectedItem
    if (-not $item) { return }
    $p = $item.Ref
    # The window closes BEFORE launching: otherwise wt opens the tab behind it and
    # Hangar stays on top like a ghost.
    $window.Close()
    switch ($Action) {
        'tab'      { Start-Project -Project $p -DryRun:$DryRun }
        'window'   { Start-Project -Project $p -DryRun:$DryRun -NewWindow }
        'continue' { Start-Project -Project $p -DryRun:$DryRun -Continue }
        'shell'    { Start-Project -Project $p -DryRun:$DryRun -ShellOnly }
        'editor'   {
            if (-not (Open-ProjectInEditor -Project $p -DryRun:$DryRun)) {
                Write-Warning "VS Code (`code`) is not on PATH."
            }
        }
        'explorer' { Open-ProjectInExplorer -Project $p -DryRun:$DryRun | Out-Null }
    }
}

function Move-Selection([int]$Delta) {
    if ($list.Items.Count -eq 0) { return }
    $next = [Math]::Max(0, [Math]::Min($list.Items.Count - 1, $list.SelectedIndex + $Delta))
    $list.SelectedIndex = $next
    $list.ScrollIntoView($list.SelectedItem)
}

# F5: refresh the index WITHOUT freezing the window. A synchronous run takes a few
# seconds (git over ~70 repos) and an event handler blocks the dispatcher — the window
# would go white. The indexer therefore runs as a background process and a
# DispatcherTimer waits for it to finish; only the cheap JSON load happens on the UI
# thread. ($script:IndexScript comes from hangar-core.ps1 — dot-sourcing put it into
# this file's script scope.)
function Start-IndexRefresh {
    if ($script:ReindexProc -and -not $script:ReindexProc.HasExited) { return }
    $countLabel.Text = 'refreshing index…'
    $script:ReindexProc = Start-Process pwsh -PassThru -WindowStyle Hidden `
        -ArgumentList '-NoProfile', '-File', $script:IndexScript
    if (-not $script:ReindexTimer) {
        $script:ReindexTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $script:ReindexTimer.Interval = [TimeSpan]::FromMilliseconds(400)
        $script:ReindexTimer.Add_Tick({
            if ($script:ReindexProc -and $script:ReindexProc.HasExited) {
                $script:ReindexTimer.Stop()
                $script:ReindexProc = $null
                Import-HangarIndex
                Update-List
            }
        })
    }
    $script:ReindexTimer.Start()
}

# --- events ---------------------------------------------------------------------------

$searchBox.Add_TextChanged({ Update-List })
$list.Add_SelectionChanged({ Update-Detail $list.SelectedItem })
$list.Add_MouseDoubleClick({ Invoke-Action 'tab' })

# PreviewKeyDown on the window, not the TextBox: arrows and Enter must be caught before
# the search box gets them, so the selection can be driven while typing. Letters, on
# the other hand, are let through, so focus can stay in the search box for good.
$window.Add_PreviewKeyDown({
    param($eventSource, $e)
    # Explicit comparison with 0: -band over an enum yields a value, not a bool, and
    # relying on its truthiness is needlessly thin ice.
    $mods  = [System.Windows.Input.Keyboard]::Modifiers
    $ctrl  = ($mods -band [System.Windows.Input.ModifierKeys]::Control) -ne 0
    $shift = ($mods -band [System.Windows.Input.ModifierKeys]::Shift)   -ne 0

    switch ($e.Key) {
        'Down'   { Move-Selection 1;  $e.Handled = $true }
        'Up'     { Move-Selection -1; $e.Handled = $true }
        'PageDown' { Move-Selection 10;  $e.Handled = $true }
        'PageUp'   { Move-Selection -10; $e.Handled = $true }
        'Escape' { $window.Close(); $e.Handled = $true }
        'F5'     { Start-IndexRefresh; $e.Handled = $true }
        'Return' {
            $action = if ($shift) { 'window' } elseif ($ctrl) { 'continue' } else { 'tab' }
            Invoke-Action $action
            $e.Handled = $true
        }
        'S' { if ($ctrl) { Invoke-Action 'shell';    $e.Handled = $true } }
        'E' { if ($ctrl) { Invoke-Action 'editor';   $e.Handled = $true } }
        'O' { if ($ctrl) { Invoke-Action 'explorer'; $e.Handled = $true } }
    }
})

$window.Add_ContentRendered({ $searchBox.Focus() | Out-Null })

Update-List
if ($Project) {
    # The TextChanged handler is already registered, so this filters right away.
    $searchBox.Text = $Project
    $searchBox.CaretIndex = $Project.Length
}
$window.ShowDialog() | Out-Null
