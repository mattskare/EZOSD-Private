<#
.SYNOPSIS
    EZOSD USB Creator - Modern WPF GUI for creating bootable USB drives.
.DESCRIPTION
    A Windows Presentation Foundation (WPF) application that wraps the
    Create-BootableUSB.ps1 script with a modern dark-themed UI featuring
    real-time log output, USB drive detection, and progress tracking.
.NOTES
    Version: 0.2.0
    Requires: PowerShell 5.1+, .NET Framework 4.5+, Administrator privileges
#>

#Requires -Version 5.1

# ─── Assembly References ───────────────────────────────────────────────────────
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# ─── Script Variables ──────────────────────────────────────────────────────────
$script:AppRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:RepoRoot = Split-Path -Parent $script:AppRoot
$script:Version = try { (Get-Content -Path (Join-Path $script:RepoRoot "VERSION") -Raw).Trim() } catch { "0.0.0" }
$script:BuildScriptPath = Join-Path $script:RepoRoot "build\Create-BootableUSB.ps1"
$script:RunningJob = $null
$script:RunspacePool = $null
# Advanced options lock state.
# UI-only guard to prevent accidental changes — not a security boundary.
# Anyone with filesystem access can edit this script. Change the value below to set a custom password.
$script:AdvancedPasswordHash = "C0D2ADE94EF162F2B88F678306396508A447E4FACD7441B6EC6E472867AD11C5"
$script:AdvancedUnlocked = $false

# ─── XAML UI Definition ────────────────────────────────────────────────────────
[xml]$xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="EZOSD USB Creator"
    Width="820" Height="700"
    MinWidth="700" MinHeight="600"
    WindowStartupLocation="CenterScreen"
    Background="#0d1117"
    Foreground="#e6edf3"
    FontFamily="Segoe UI"
    FontSize="13">

    <Window.Resources>
        <!-- Accent Colors -->
        <SolidColorBrush x:Key="AccentBrush" Color="#58a6ff"/>
        <SolidColorBrush x:Key="AccentHoverBrush" Color="#79c0ff"/>
        <SolidColorBrush x:Key="SuccessBrush" Color="#3fb950"/>
        <SolidColorBrush x:Key="WarningBrush" Color="#d29922"/>
        <SolidColorBrush x:Key="ErrorBrush" Color="#f85149"/>
        <SolidColorBrush x:Key="CardBg" Color="#161b22"/>
        <SolidColorBrush x:Key="CardBorder" Color="#30363d"/>
        <SolidColorBrush x:Key="InputBg" Color="#0d1117"/>
        <SolidColorBrush x:Key="InputBorder" Color="#30363d"/>
        <SolidColorBrush x:Key="SubtleText" Color="#8b949e"/>

        <!-- Modern Button Style -->
        <Style x:Key="ModernButton" TargetType="Button">
            <Setter Property="Background" Value="#21262d"/>
            <Setter Property="Foreground" Value="#e6edf3"/>
            <Setter Property="BorderBrush" Value="#30363d"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="16,8"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#30363d"/>
                                <Setter TargetName="border" Property="BorderBrush" Value="#484f58"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#161b22"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Primary Button Style -->
        <Style x:Key="PrimaryButton" TargetType="Button" BasedOn="{StaticResource ModernButton}">
            <Setter Property="Background" Value="#238636"/>
            <Setter Property="BorderBrush" Value="#2ea043"/>
            <Setter Property="Foreground" Value="#ffffff"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="1"
                                CornerRadius="6"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#2ea043"/>
                                <Setter TargetName="border" Property="BorderBrush" Value="#3fb950"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#196c2e"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Danger Button Style -->
        <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource ModernButton}">
            <Setter Property="Background" Value="#da3633"/>
            <Setter Property="BorderBrush" Value="#f85149"/>
            <Setter Property="Foreground" Value="#ffffff"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="1"
                                CornerRadius="6"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#f85149"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#b62324"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Modern ComboBox Item Style -->
        <Style TargetType="ComboBoxItem">
            <Setter Property="Background" Value="#161b22"/>
            <Setter Property="Foreground" Value="#e6edf3"/>
            <Setter Property="Padding" Value="10,7"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBoxItem">
                        <Border x:Name="itemBorder"
                                Background="{TemplateBinding Background}"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsHighlighted" Value="True">
                                <Setter TargetName="itemBorder" Property="Background" Value="#21262d"/>
                                <Setter Property="Foreground" Value="#e6edf3"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="itemBorder" Property="Background" Value="#1f3a5f"/>
                                <Setter Property="Foreground" Value="#58a6ff"/>
                            </Trigger>
                            <MultiTrigger>
                                <MultiTrigger.Conditions>
                                    <Condition Property="IsHighlighted" Value="True"/>
                                    <Condition Property="IsSelected" Value="True"/>
                                </MultiTrigger.Conditions>
                                <Setter TargetName="itemBorder" Property="Background" Value="#1f3a5f"/>
                                <Setter Property="Foreground" Value="#79c0ff"/>
                            </MultiTrigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Modern ComboBox Style -->
        <Style TargetType="ComboBox">
            <Setter Property="Background" Value="#21262d"/>
            <Setter Property="Foreground" Value="#e6edf3"/>
            <Setter Property="BorderBrush" Value="#30363d"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,8"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBox">
                        <Grid>
                            <Border x:Name="mainBorder"
                                    Background="{TemplateBinding Background}"
                                    BorderBrush="{TemplateBinding BorderBrush}"
                                    BorderThickness="{TemplateBinding BorderThickness}"
                                    CornerRadius="6">
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="28"/>
                                    </Grid.ColumnDefinitions>
                                    <!-- Selected text -->
                                    <ContentPresenter x:Name="contentPresenter"
                                                      Grid.Column="0"
                                                      Content="{TemplateBinding SelectionBoxItem}"
                                                      ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                                      Margin="{TemplateBinding Padding}"
                                                      VerticalAlignment="Center"
                                                      IsHitTestVisible="False"
                                                      TextBlock.Foreground="{TemplateBinding Foreground}"/>
                                    <!-- Arrow -->
                                    <Path Grid.Column="1" Data="M 0 0 L 5 5 L 10 0"
                                          Stroke="#8b949e" StrokeThickness="1.5"
                                          HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                    <!-- Hidden toggle -->
                                    <ToggleButton Grid.ColumnSpan="2"
                                                  IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}"
                                                  Background="Transparent" BorderThickness="0"
                                                  Focusable="False" ClickMode="Press"/>
                                </Grid>
                            </Border>
                            <!-- Dropdown popup -->
                            <Popup x:Name="PART_Popup"
                                   IsOpen="{TemplateBinding IsDropDownOpen}"
                                   AllowsTransparency="True"
                                   Focusable="False"
                                   PopupAnimation="Slide"
                                   Placement="Bottom"
                                   PlacementTarget="{Binding ElementName=mainBorder}">
                                <Border Background="#161b22"
                                        BorderBrush="#30363d"
                                        BorderThickness="1"
                                        CornerRadius="6"
                                        MinWidth="{Binding ActualWidth, ElementName=mainBorder}"
                                        MaxHeight="220"
                                        Margin="0,4,0,0"
                                        SnapsToDevicePixels="True">
                                    <ScrollViewer VerticalScrollBarVisibility="Auto"
                                                  Background="Transparent">
                                        <ItemsPresenter/>
                                    </ScrollViewer>
                                </Border>
                            </Popup>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="mainBorder" Property="BorderBrush" Value="#484f58"/>
                                <Setter TargetName="mainBorder" Property="Background" Value="#30363d"/>
                            </Trigger>
                            <Trigger Property="IsDropDownOpen" Value="True">
                                <Setter TargetName="mainBorder" Property="BorderBrush" Value="#58a6ff"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Modern TextBox Style -->
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#0d1117"/>
            <Setter Property="Foreground" Value="#e6edf3"/>
            <Setter Property="BorderBrush" Value="#30363d"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,8"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="CaretBrush" Value="#e6edf3"/>
        </Style>

        <!-- Modern CheckBox Style -->
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="#e6edf3"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>

        <!-- Card Border Style -->
        <Style x:Key="Card" TargetType="Border">
            <Setter Property="Background" Value="#161b22"/>
            <Setter Property="BorderBrush" Value="#30363d"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="8"/>
            <Setter Property="Padding" Value="20,16"/>
        </Style>
    </Window.Resources>

    <Grid Margin="24,16,24,20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- ─── Header ─── -->
        <StackPanel Grid.Row="0" Margin="0,0,0,20">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                <TextBlock Text="&#xE7F8;" FontFamily="Segoe MDL2 Assets" FontSize="28"
                           Foreground="{StaticResource AccentBrush}" VerticalAlignment="Center" Margin="0,0,12,0"/>
                <StackPanel>
                    <TextBlock Text="EZOSD USB Creator" FontSize="22" FontWeight="SemiBold" Foreground="#e6edf3"/>
                    <TextBlock x:Name="VersionText" FontSize="12" Foreground="{StaticResource SubtleText}" Margin="0,2,0,0"/>
                </StackPanel>
            </StackPanel>
        </StackPanel>

        <!-- ─── Configuration Card ─── -->
        <Border Grid.Row="1" Style="{StaticResource Card}" Margin="0,0,0,16">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="140"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <!-- Section Title -->
                <TextBlock Grid.Row="0" Grid.ColumnSpan="3" Text="Configuration"
                           FontSize="15" FontWeight="SemiBold" Foreground="{StaticResource AccentBrush}"
                           Margin="0,0,0,16"/>

                <!-- USB Drive -->
                <TextBlock Grid.Row="1" Grid.Column="0" Text="USB Drive"
                           VerticalAlignment="Center" Foreground="{StaticResource SubtleText}" Margin="0,0,0,12"/>
                <ComboBox x:Name="USBDriveCombo" Grid.Row="1" Grid.Column="1"
                          Margin="0,0,8,12" IsEditable="False"/>
                <Button x:Name="RefreshDrivesBtn" Grid.Row="1" Grid.Column="2"
                        Style="{StaticResource ModernButton}" Margin="0,0,0,12" Padding="12,8">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="&#xE72C;" FontFamily="Segoe MDL2 Assets" VerticalAlignment="Center" Margin="0,0,6,0"/>
                        <TextBlock Text="Refresh" VerticalAlignment="Center"/>
                    </StackPanel>
                </Button>

                <!-- Advanced Options Header -->
                <Border Grid.Row="2" Grid.ColumnSpan="3" Margin="0,4,0,0"
                        BorderBrush="#21262d" BorderThickness="0,1,0,0" Padding="0,10,0,0">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <Button x:Name="AdvExpandBtn" Grid.Column="0"
                                HorizontalContentAlignment="Left" Padding="0" Cursor="Hand"
                                Background="Transparent" BorderThickness="0"
                                ToolTip="Expand/collapse advanced options">
                            <Button.Template>
                                <ControlTemplate TargetType="Button">
                                    <Border Background="{TemplateBinding Background}"
                                            Padding="{TemplateBinding Padding}">
                                        <ContentPresenter/>
                                    </Border>
                                </ControlTemplate>
                            </Button.Template>
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock x:Name="AdvChevron" Text="&#xE76C;"
                                           FontFamily="Segoe MDL2 Assets" FontSize="10"
                                           Foreground="#484f58" VerticalAlignment="Center"
                                           Margin="0,0,8,0"/>
                                <TextBlock x:Name="AdvLockIcon" Text="&#xE72E;"
                                           FontFamily="Segoe MDL2 Assets" FontSize="12"
                                           Foreground="#d29922" VerticalAlignment="Center"
                                           Margin="0,0,6,0"/>
                                <TextBlock Text="Advanced Options" FontSize="12"
                                           Foreground="#8b949e" VerticalAlignment="Center"/>
                            </StackPanel>
                        </Button>
                        <Button x:Name="AdvLockBtn" Grid.Column="1"
                                Style="{StaticResource ModernButton}" Padding="10,5">
                            <TextBlock x:Name="AdvLockBtnText" Text="Unlock"
                                       FontSize="11" Foreground="#d29922"/>
                        </Button>
                    </Grid>
                </Border>

                <!-- Advanced Options Body (collapsed and locked by default) -->
                <Grid x:Name="AdvancedPanel" Grid.Row="3" Grid.ColumnSpan="3"
                      Visibility="Collapsed" Margin="0,12,0,0">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="140"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>

                        <!-- ADK Path -->
                        <TextBlock Grid.Row="0" Grid.Column="0" Text="ADK Path"
                                   VerticalAlignment="Center" Foreground="{StaticResource SubtleText}" Margin="0,0,0,12"/>
                        <TextBox x:Name="ADKPathText" Grid.Row="0" Grid.Column="1"
                                 Margin="0,0,8,12" ToolTip="Leave empty for auto-detection"
                                 IsEnabled="False"/>
                        <Button x:Name="BrowseADKBtn" Grid.Row="0" Grid.Column="2"
                                Content="Browse..." Style="{StaticResource ModernButton}"
                                Margin="0,0,0,12" Padding="12,8" IsEnabled="False"/>

                        <!-- Working Directory -->
                        <TextBlock Grid.Row="1" Grid.Column="0" Text="Working Directory"
                                   VerticalAlignment="Center" Foreground="{StaticResource SubtleText}" Margin="0,0,0,12"/>
                        <TextBox x:Name="WorkDirText" Grid.Row="1" Grid.Column="1"
                                 Text="C:\EZOSD" Margin="0,0,8,12" IsEnabled="False"/>
                        <Button x:Name="BrowseWorkDirBtn" Grid.Row="1" Grid.Column="2"
                                Content="Browse..." Style="{StaticResource ModernButton}"
                                Margin="0,0,0,12" Padding="12,8" IsEnabled="False"/>

                        <!-- Options -->
                        <TextBlock Grid.Row="2" Grid.Column="0" Text="Options"
                                   VerticalAlignment="Center" Foreground="{StaticResource SubtleText}"/>
                        <CheckBox x:Name="OptionalPkgCheck" Grid.Row="2" Grid.Column="1"
                                  Content="Include optional WinPE packages (SecureStartup, EnhancedStorage, FMAPI)"
                                  Grid.ColumnSpan="2" IsEnabled="False"/>
                    </Grid>
                </Grid>
            </Grid>
        </Border>

        <!-- ─── Action Bar ─── -->
        <Grid Grid.Row="2" Margin="0,0,0,16">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>

            <!-- Status -->
            <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                <Ellipse x:Name="StatusDot" Width="10" Height="10" Fill="{StaticResource SubtleText}" Margin="0,0,8,0"/>
                <TextBlock x:Name="StatusText" Text="Ready" Foreground="{StaticResource SubtleText}" FontSize="13"/>
            </StackPanel>

            <!-- Buttons -->
            <Button x:Name="CancelBtn" Grid.Column="1" Content="Cancel"
                    Style="{StaticResource DangerButton}" Margin="0,0,10,0"
                    Padding="20,10" Visibility="Collapsed"/>
            <Button x:Name="StartBtn" Grid.Column="2"
                    Style="{StaticResource PrimaryButton}" Padding="24,10">
                <StackPanel Orientation="Horizontal">
                    <TextBlock Text="&#xE768;" FontFamily="Segoe MDL2 Assets" VerticalAlignment="Center" Margin="0,0,8,0"/>
                    <TextBlock Text="Create Bootable USB" VerticalAlignment="Center"/>
                </StackPanel>
            </Button>
        </Grid>

        <!-- ─── Log Output Card ─── -->
        <Border Grid.Row="3" Style="{StaticResource Card}" Padding="0">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>

                <!-- Log Header -->
                <Border Grid.Row="0" Background="#1c2128" CornerRadius="8,8,0,0" Padding="16,10">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="&#xE7BA;" FontFamily="Segoe MDL2 Assets" FontSize="14"
                                       Foreground="{StaticResource SubtleText}" VerticalAlignment="Center" Margin="0,0,8,0"/>
                            <TextBlock Text="Output Log" FontSize="13" Foreground="{StaticResource SubtleText}"/>
                        </StackPanel>
                        <Button x:Name="ClearLogBtn" Grid.Column="1" Content="Clear"
                                Style="{StaticResource ModernButton}" Padding="10,4" FontSize="11"/>
                    </Grid>
                </Border>

                <!-- Log Content -->
                <RichTextBox x:Name="LogOutput" Grid.Row="1"
                             Background="#0d1117" Foreground="#e6edf3"
                             BorderThickness="0" IsReadOnly="True"
                             VerticalScrollBarVisibility="Auto"
                             HorizontalScrollBarVisibility="Auto"
                             FontFamily="Cascadia Code, Cascadia Mono, Consolas, Courier New"
                             FontSize="12" Padding="16,12"
                             Block.LineHeight="2">
                    <FlowDocument>
                        <Paragraph>
                            <Run Text="Waiting to start..." Foreground="#8b949e"/>
                        </Paragraph>
                    </FlowDocument>
                </RichTextBox>
            </Grid>
        </Border>

        <!-- ─── Footer ─── -->
        <Border Grid.Row="4" Margin="0,12,0,0">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock Grid.Column="0" FontSize="11" Foreground="#484f58">
                    <Run Text="Requires: Administrator privileges, Windows ADK"/>
                </TextBlock>
                <TextBlock x:Name="ProgressText" Grid.Column="1" FontSize="11"
                           Foreground="{StaticResource SubtleText}"/>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

# ─── Create Window ─────────────────────────────────────────────────────────────
$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# ─── Locate Controls ──────────────────────────────────────────────────────────
$controls = @{}
$controlNames = @(
    'VersionText', 'USBDriveCombo', 'RefreshDrivesBtn', 'ADKPathText',
    'BrowseADKBtn', 'WorkDirText', 'BrowseWorkDirBtn', 'OptionalPkgCheck',
    'StatusDot', 'StatusText', 'CancelBtn', 'StartBtn',
    'LogOutput', 'ClearLogBtn', 'ProgressText',
    'AdvExpandBtn', 'AdvChevron', 'AdvLockIcon', 'AdvLockBtn', 'AdvLockBtnText', 'AdvancedPanel'
)
foreach ($name in $controlNames) {
    $controls[$name] = $window.FindName($name)
}

$controls['VersionText'].Text = "v$script:Version  —  Bootable USB Creation Tool"

# ─── Helper Functions ──────────────────────────────────────────────────────────

function Get-RemovableDrives {
    $drives = @()
    try {
        Get-Disk | Where-Object { $_.BusType -eq 'USB' -or $_.BusType -eq 'SD' } | Sort-Object Number | ForEach-Object {
            $disk = $_
            $sizeGB = [math]::Round($disk.Size / 1GB, 1)
            # Find most prominent drive letter on this disk (if any)
            $driveLetter = Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue |
                Where-Object { $_.DriveLetter } |
                Select-Object -First 1 -ExpandProperty DriveLetter
            $letterLabel = if ($driveLetter) { "($($driveLetter):) " } else { "(no drive letter) " }
            $drives += [PSCustomObject]@{
                Display    = "Disk $($disk.Number)  $letterLabel—  $($disk.FriendlyName) ($sizeGB GB)"
                DiskNumber = $disk.Number
                SizeGB     = $sizeGB
            }
        }
    }
    catch {
        # Silently handle — may not have admin rights yet
    }
    return $drives
}

function Update-DriveList {
    $controls['USBDriveCombo'].Items.Clear()
    $script:DriveMap = @{}

    $drives = Get-RemovableDrives
    if ($drives.Count -eq 0) {
        $controls['USBDriveCombo'].Items.Add("No removable drives detected") | Out-Null
        $controls['USBDriveCombo'].SelectedIndex = 0
        $controls['USBDriveCombo'].IsEnabled = $false
        $controls['StartBtn'].IsEnabled = $false
    }
    else {
        $controls['USBDriveCombo'].IsEnabled = $true
        $controls['StartBtn'].IsEnabled = $true
        foreach ($d in $drives) {
            $controls['USBDriveCombo'].Items.Add($d.Display) | Out-Null
            $script:DriveMap[$d.Display] = $d
        }
        $controls['USBDriveCombo'].SelectedIndex = 0
    }
}

function Set-UIState {
    param([ValidateSet('Ready', 'Running', 'Success', 'Error')]$State)

    switch ($State) {
        'Ready' {
            $controls['StatusDot'].Fill = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8b949e")
            $controls['StatusText'].Text = "Ready"
            $controls['StatusText'].Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8b949e")
            $controls['StartBtn'].IsEnabled = $true
            $controls['StartBtn'].Visibility = 'Visible'
            $controls['CancelBtn'].Visibility = 'Collapsed'
            $controls['ProgressText'].Text = ""
        }
        'Running' {
            $controls['StatusDot'].Fill = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#58a6ff")
            $controls['StatusText'].Text = "Building..."
            $controls['StatusText'].Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#58a6ff")
            $controls['StartBtn'].IsEnabled = $false
            $controls['StartBtn'].Visibility = 'Collapsed'
            $controls['CancelBtn'].Visibility = 'Visible'
        }
        'Success' {
            $controls['StatusDot'].Fill = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#3fb950")
            $controls['StatusText'].Text = "Completed successfully"
            $controls['StatusText'].Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#3fb950")
            $controls['StartBtn'].IsEnabled = $true
            $controls['StartBtn'].Visibility = 'Visible'
            $controls['CancelBtn'].Visibility = 'Collapsed'
        }
        'Error' {
            $controls['StatusDot'].Fill = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#f85149")
            $controls['StatusText'].Text = "Build failed"
            $controls['StatusText'].Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#f85149")
            $controls['StartBtn'].IsEnabled = $true
            $controls['StartBtn'].Visibility = 'Visible'
            $controls['CancelBtn'].Visibility = 'Collapsed'
        }
    }
}

function Write-LogMessage {
    param(
        [string]$Message,
        [string]$Color = "#e6edf3"
    )

    $window.Dispatcher.Invoke([Action]{
        $doc = $controls['LogOutput'].Document
        $para = [System.Windows.Documents.Paragraph]::new()
        $para.LineHeight = 2
        $para.Margin = [System.Windows.Thickness]::new(0, 0, 0, 1)

        $run = [System.Windows.Documents.Run]::new($Message)
        $run.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom($Color)
        $para.Inlines.Add($run)
        $doc.Blocks.Add($para)

        $controls['LogOutput'].ScrollToEnd()
    }, [System.Windows.Threading.DispatcherPriority]::Background)
}

function Clear-Log {
    $doc = $controls['LogOutput'].Document
    $doc.Blocks.Clear()
}

function Show-FolderBrowser {
    param([string]$Description = "Select Folder")

    $dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $true

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    }
    return $null
}

# ─── Password Dialog ──────────────────────────────────────────────────────────

function Show-PasswordDialog {
    [xml]$pwXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Advanced Options" Width="400" Height="210"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        Background="#0d1117" Foreground="#e6edf3"
        FontFamily="Segoe UI" FontSize="13">
    <StackPanel Margin="24,20,24,20">
        <StackPanel Orientation="Horizontal" Margin="0,0,0,14">
            <TextBlock Text="&#xE72E;" FontFamily="Segoe MDL2 Assets" FontSize="18"
                       Foreground="#d29922" VerticalAlignment="Center" Margin="0,0,10,0"/>
            <TextBlock Text="Enter the password to unlock advanced options."
                       Foreground="#8b949e" VerticalAlignment="Center" TextWrapping="Wrap"/>
        </StackPanel>
        <PasswordBox x:Name="PwInput"
                     Background="#21262d" Foreground="#e6edf3"
                     BorderBrush="#30363d" BorderThickness="1"
                     Padding="10,8" FontSize="13" CaretBrush="#e6edf3"/>
        <TextBlock x:Name="PwError" Text="Incorrect password."
                   FontSize="11" Foreground="#f85149"
                   Margin="0,6,0,0" Visibility="Collapsed"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
            <Button x:Name="PwCancelBtn" Content="Cancel"
                    Background="#21262d" Foreground="#e6edf3"
                    BorderBrush="#30363d" BorderThickness="1"
                    Padding="16,8" Margin="0,0,8,0" Cursor="Hand"/>
            <Button x:Name="PwOKBtn" Content="Unlock"
                    Background="#238636" Foreground="#ffffff"
                    BorderBrush="#2ea043" BorderThickness="1"
                    Padding="16,8" Cursor="Hand"/>
        </StackPanel>
    </StackPanel>
</Window>
"@
    $pwReader  = [System.Xml.XmlNodeReader]::new($pwXaml)
    $pwWindow  = [System.Windows.Markup.XamlReader]::Load($pwReader)
    $pwWindow.Owner = $window

    $pwInput  = $pwWindow.FindName('PwInput')
    $pwError  = $pwWindow.FindName('PwError')
    $pwOK     = $pwWindow.FindName('PwOKBtn')
    $pwCancel = $pwWindow.FindName('PwCancelBtn')

    $script:_PwResult = $false

    $pwOK.Add_Click({
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $bytes  = [System.Text.Encoding]::UTF8.GetBytes($pwInput.Password)
        $hash   = [BitConverter]::ToString($sha256.ComputeHash($bytes)).Replace('-','')
        $sha256.Dispose()
        if ($hash -eq $script:AdvancedPasswordHash) {
            $script:_PwResult = $true
            $pwWindow.Close()
        }
        else {
            $pwError.Visibility = 'Visible'
            $pwInput.Clear()
            $pwInput.Focus() | Out-Null
        }
    })

    $pwCancel.Add_Click({ $pwWindow.Close() })

    $pwInput.Add_KeyDown({
        if ($_.Key -eq [System.Windows.Input.Key]::Return) {
            $pwOK.RaiseEvent(
                [System.Windows.RoutedEventArgs]::new(
                    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
                )
            )
        }
    })

    $pwWindow.ShowDialog() | Out-Null
    return $script:_PwResult
}

# ─── Event Handlers ────────────────────────────────────────────────────────────

# Advanced options — expand/collapse (only works when unlocked)
$controls['AdvExpandBtn'].Add_Click({
    if (-not $script:AdvancedUnlocked) { return }
    $brush = [System.Windows.Media.BrushConverter]::new()
    if ($controls['AdvancedPanel'].Visibility -eq 'Collapsed') {
        $controls['AdvancedPanel'].Visibility = 'Visible'
        $controls['AdvChevron'].Text          = [char]0xE70D   # ChevronDown
        $controls['AdvChevron'].Foreground    = $brush.ConvertFrom('#8b949e')
    }
    else {
        $controls['AdvancedPanel'].Visibility = 'Collapsed'
        $controls['AdvChevron'].Text          = [char]0xE76C   # ChevronRight
        $controls['AdvChevron'].Foreground    = $brush.ConvertFrom('#484f58')
    }
})

# Advanced options — lock / unlock
$controls['AdvLockBtn'].Add_Click({
    $brush = [System.Windows.Media.BrushConverter]::new()
    if ($script:AdvancedUnlocked) {
        # Re-lock: collapse and disable all advanced controls
        $script:AdvancedUnlocked = $false
        $controls['AdvancedPanel'].Visibility   = 'Collapsed'
        $controls['AdvChevron'].Text            = [char]0xE76C
        $controls['AdvChevron'].Foreground      = $brush.ConvertFrom('#484f58')
        $controls['AdvLockIcon'].Foreground     = $brush.ConvertFrom('#d29922')
        $controls['AdvLockBtnText'].Text        = 'Unlock'
        $controls['AdvLockBtnText'].Foreground  = $brush.ConvertFrom('#d29922')
        $controls['ADKPathText'].IsEnabled      = $false
        $controls['WorkDirText'].IsEnabled      = $false
        $controls['BrowseADKBtn'].IsEnabled     = $false
        $controls['BrowseWorkDirBtn'].IsEnabled = $false
        $controls['OptionalPkgCheck'].IsEnabled = $false
    }
    else {
        # Prompt for password; unlock on success
        if (Show-PasswordDialog) {
            $script:AdvancedUnlocked = $true
            $controls['AdvancedPanel'].Visibility   = 'Visible'
            $controls['AdvChevron'].Text            = [char]0xE70D
            $controls['AdvChevron'].Foreground      = $brush.ConvertFrom('#8b949e')
            $controls['AdvLockIcon'].Foreground     = $brush.ConvertFrom('#3fb950')
            $controls['AdvLockBtnText'].Text        = 'Lock'
            $controls['AdvLockBtnText'].Foreground  = $brush.ConvertFrom('#3fb950')
            $controls['ADKPathText'].IsEnabled      = $true
            $controls['WorkDirText'].IsEnabled      = $true
            $controls['BrowseADKBtn'].IsEnabled     = $true
            $controls['BrowseWorkDirBtn'].IsEnabled = $true
            $controls['OptionalPkgCheck'].IsEnabled = $true
        }
    }
})

# Refresh drives
$controls['RefreshDrivesBtn'].Add_Click({
    Update-DriveList
    Write-LogMessage "[*] Drive list refreshed" "#8b949e"
})

# Browse ADK
$controls['BrowseADKBtn'].Add_Click({
    $path = Show-FolderBrowser -Description "Select Windows ADK installation folder"
    if ($path) { $controls['ADKPathText'].Text = $path }
})

# Browse work dir
$controls['BrowseWorkDirBtn'].Add_Click({
    $path = Show-FolderBrowser -Description "Select working directory"
    if ($path) { $controls['WorkDirText'].Text = $path }
})

# Clear log
$controls['ClearLogBtn'].Add_Click({
    Clear-Log
})

# Cancel
$controls['CancelBtn'].Add_Click({
    if ($script:RunningJob) {
        try {
            $script:RunningJob.PowerShell.Stop()
            $script:RunningJob.PowerShell.Dispose()
        } catch {}
        $script:RunningJob = $null
        Write-LogMessage ""
        Write-LogMessage "[!] Build cancelled by user" "#d29922"
        Set-UIState -State 'Ready'
    }
})

# Start Build
$controls['StartBtn'].Add_Click({
    # Validate selection
    $selectedDisplay = $controls['USBDriveCombo'].SelectedItem
    if (-not $selectedDisplay -or -not $script:DriveMap.ContainsKey($selectedDisplay)) {
        [System.Windows.MessageBox]::Show(
            "Please select a valid USB drive.",
            "EZOSD USB Creator",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning
        )
        return
    }

    $driveInfo = $script:DriveMap[$selectedDisplay]
    $diskNumber = $driveInfo.DiskNumber

    # Confirm destructive operation
    $confirm = [System.Windows.MessageBox]::Show(
        "WARNING: ALL DATA on Disk $diskNumber ($($driveInfo.Display)) will be erased.`n`nThis operation cannot be undone. Continue?",
        "Confirm USB Format",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning
    )

    if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) {
        return
    }

    # Gather parameters
    $adkPath = $controls['ADKPathText'].Text.Trim()
    $workDir = $controls['WorkDirText'].Text.Trim()
    $includeOptional = $controls['OptionalPkgCheck'].IsChecked

    # Prepare UI
    Clear-Log
    Set-UIState -State 'Running'
    $script:StartTime = [datetime]::Now

    Write-LogMessage "╔═══════════════════════════════════════════════════════════════╗" "#58a6ff"
    Write-LogMessage "║           EZOSD Bootable USB Creation Tool                    ║" "#58a6ff"
    Write-LogMessage "║                    Version $script:Version                              ║" "#58a6ff"
    Write-LogMessage "╚═══════════════════════════════════════════════════════════════╝" "#58a6ff"
    Write-LogMessage ""
    Write-LogMessage "[*] Target Disk: $diskNumber ($($driveInfo.Display))"
    Write-LogMessage "[*] Working Dir: $workDir"
    if ($adkPath) { Write-LogMessage "[*] ADK Path: $adkPath" }
    if ($includeOptional) { Write-LogMessage "[*] Optional packages: enabled" }
    Write-LogMessage ""

    # Timer to update elapsed time
    $script:Timer = [System.Windows.Threading.DispatcherTimer]::new()
    $script:Timer.Interval = [TimeSpan]::FromSeconds(1)
    $script:Timer.Add_Tick({
        if ($script:StartTime) {
            $elapsed = [datetime]::Now - $script:StartTime
            $controls['ProgressText'].Text = "Elapsed: $($elapsed.ToString('mm\:ss'))"
        }
    })
    $script:Timer.Start()

    # Run in a background runspace so the UI stays responsive
    $script:RunspacePool = [RunspaceFactory]::CreateRunspacePool(1, 1)
    $script:RunspacePool.ApartmentState = 'STA'
    $script:RunspacePool.Open()

    $ps = [PowerShell]::Create()
    $ps.RunspacePool = $script:RunspacePool

    # Synchronized hashtable for passing output between runspace and UI
    $syncHash = [hashtable]::Synchronized(@{
        Window       = $window
        Controls     = $controls
        ScriptPath   = $script:BuildScriptPath
        RepoRoot     = $script:RepoRoot
        DiskNumber   = $diskNumber
        ADKPath      = $adkPath
        WorkDir      = $workDir
        IncludeOpt   = $includeOptional
        Done         = $false
        Success      = $false
        ErrorMsg     = ""
    })

    $ps.AddScript({
        param($sync)

        try {
            # Build the argument list
            $params = @{
                DiskNumber = $sync.DiskNumber
                Directory  = $sync.WorkDir
            }
            if ($sync.ADKPath) { $params['ADKPath'] = $sync.ADKPath }
            if ($sync.IncludeOpt) { $params['IncludeOptionalPackages'] = $true }

            # Redirect output by running the script and capturing streams
            Set-Location $sync.RepoRoot

            $output = & $sync.ScriptPath @params *>&1

            foreach ($line in $output) {
                $text = $line.ToString()
                $color = "#e6edf3"

                if ($line -is [System.Management.Automation.ErrorRecord]) {
                    $color = "#f85149"
                    $text = "[ERROR] $text"
                }
                elseif ($line -is [System.Management.Automation.WarningRecord]) {
                    $color = "#d29922"
                    $text = "[WARN] $text"
                }
                elseif ($line -is [System.Management.Automation.VerboseRecord]) {
                    $color = "#8b949e"
                    $text = "[VERBOSE] $text"
                }
                elseif ($text -match '\[✓\]|successfully|SUCCESS') {
                    $color = "#3fb950"
                }
                elseif ($text -match '\[!\]|Warning') {
                    $color = "#d29922"
                }
                elseif ($text -match '\[✗\]|Error|FAILED') {
                    $color = "#f85149"
                }
                elseif ($text -match '═|║|╔|╗|╚|╝') {
                    $color = "#58a6ff"
                }

                $sync.Window.Dispatcher.Invoke([Action]{
                    $doc = $sync.Controls['LogOutput'].Document
                    $para = [System.Windows.Documents.Paragraph]::new()
                    $para.LineHeight = 2
                    $para.Margin = [System.Windows.Thickness]::new(0, 0, 0, 1)
                    $run = [System.Windows.Documents.Run]::new($text)
                    $run.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom($color)
                    $para.Inlines.Add($run)
                    $doc.Blocks.Add($para)
                    $sync.Controls['LogOutput'].ScrollToEnd()
                }, [System.Windows.Threading.DispatcherPriority]::Background)
            }

            $sync.Success = $true
        }
        catch {
            $sync.ErrorMsg = $_.Exception.Message
            $sync.Success = $false

            $sync.Window.Dispatcher.Invoke([Action]{
                $doc = $sync.Controls['LogOutput'].Document
                $para = [System.Windows.Documents.Paragraph]::new()
                $para.LineHeight = 2
                $run = [System.Windows.Documents.Run]::new("[ERROR] $($sync.ErrorMsg)")
                $run.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#f85149")
                $para.Inlines.Add($run)
                $doc.Blocks.Add($para)
                $sync.Controls['LogOutput'].ScrollToEnd()
            }, [System.Windows.Threading.DispatcherPriority]::Background)
        }
        finally {
            $sync.Done = $true

            $sync.Window.Dispatcher.Invoke([Action]{
                if ($sync.Success) {
                    $sync.Controls['StatusDot'].Fill = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#3fb950")
                    $sync.Controls['StatusText'].Text = "Completed successfully"
                    $sync.Controls['StatusText'].Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#3fb950")
                }
                else {
                    $sync.Controls['StatusDot'].Fill = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#f85149")
                    $sync.Controls['StatusText'].Text = "Build failed"
                    $sync.Controls['StatusText'].Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#f85149")
                }

                $sync.Controls['StartBtn'].IsEnabled = $true
                $sync.Controls['StartBtn'].Visibility = 'Visible'
                $sync.Controls['CancelBtn'].Visibility = 'Collapsed'
            }, [System.Windows.Threading.DispatcherPriority]::Background)
        }
    }).AddArgument($syncHash)

    $script:RunningJob = @{
        PowerShell = $ps
        Handle     = $ps.BeginInvoke()
        SyncHash   = $syncHash
    }
})

# ─── Window Events ─────────────────────────────────────────────────────────────

$window.Add_Loaded({
    # Check admin privileges
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )

    if (-not $isAdmin) {
        Write-LogMessage "[!] ERROR: Not running as Administrator. USB creation requires elevated privileges." "#f85149"
        Write-LogMessage "[*] Please restart this application as Administrator." "#f85149"
        Write-LogMessage ""
        $controls['StartBtn'].IsEnabled = $false
    }

    # Verify build script exists
    if (-not (Test-Path $script:BuildScriptPath)) {
        Write-LogMessage "[!] Build script not found: $($script:BuildScriptPath)" "#f85149"
        Write-LogMessage "[*] Ensure the EZOSD repository is intact." "#8b949e"
        $controls['StartBtn'].IsEnabled = $false
    }

    Update-DriveList
})

$window.Add_Closing({
    if ($script:Timer) { $script:Timer.Stop() }
    if ($script:RunningJob) {
        try {
            $script:RunningJob.PowerShell.Stop()
            $script:RunningJob.PowerShell.Dispose()
        } catch {}
    }
    if ($script:RunspacePool) {
        try { $script:RunspacePool.Close() } catch {}
    }
})

# ─── Set App Icon (from system shell32.dll USB icon) ───────────────────────────
try {
    $iconPath = [System.IO.Path]::Combine($env:SystemRoot, "System32", "shell32.dll")
    if (Test-Path $iconPath) {
        # Only P/Invoke here — no WPF assembly references in C# to avoid version conflicts.
        # The actual BitmapSource creation happens in PowerShell where assemblies are already loaded.
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class NativeIcon {
    [DllImport("shell32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr ExtractIcon(IntPtr hInst, string lpszExeFileName, int nIconIndex);

    [DllImport("user32.dll")]
    public static extern bool DestroyIcon(IntPtr hIcon);
}
"@
        $hIcon = [NativeIcon]::ExtractIcon([IntPtr]::Zero, $iconPath, 8)
        if ($hIcon -ne [IntPtr]::Zero) {
            $bitmapSource = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon(
                $hIcon,
                [System.Windows.Int32Rect]::Empty,
                [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions()
            )
            [NativeIcon]::DestroyIcon($hIcon) | Out-Null
            $window.Icon = $bitmapSource
        }
    }
}
catch {
    # Non-critical — skip icon
}

# ─── Launch ────────────────────────────────────────────────────────────────────
$window.ShowDialog() | Out-Null
