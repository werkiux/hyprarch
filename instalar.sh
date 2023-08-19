#!/bin/bash

#-------------------------------------------------#
# Establecer colores para los mensajes de salida. #
#-------------------------------------------------#
NOTA="[\e[1;36mNOTA\e[0m]"
OK="[\e[1;32mOK\e[0m]"
ERROR="[\e[1;31mERROR\e[0m]"
ATE="[\e[1;37mATENCION\e[0m]"
AVISO="[\e[1;35mAVISO\e[0m]"
#OPCION="[\e[1;33mACCION\e[0m]"
OPC="$(tput setaf 6)[OPCION]$(tput sgr0)"
VERD='\033[0;32m'

#----------------------------------------------------------------------------------------#
# Establecer el nombre del archivo de registro para incluir la fecha y la hora actuales. #
#----------------------------------------------------------------------------------------#

LOG="loginstal-$(date +%d-%H%M%S).log"

echo ""
echo "         #####################################################"
echo "         #                     BIENVENIDO!                   #"
echo "         #####################################################"
echo ""
printf "\n"
sleep 2

# Imprimir mensaje de advertencia de contraseña.
echo -e "$ATE - Algunos comandos requieren que ingrese su contraseña para poder ejecutarse. \nSi le preocupa ingresar su contraseña, puede cancelar la instalación y revisar el contenido de este script."
printf "\n"
sleep 2

# Continuar con la instalacion.
read -n1 -rep "$OPC ¿Desea continuar con la instalación? (s/n) " INST
if [[ $INST =~ ^[Ss]$ ]]; then
    echo -e "$OK - Iniciando la instalación...\n"
else
    echo -e "$NOTA - Saliendo del script, no se realizaron cambios en su sistema."
    exit
fi

#----------------------------------------------------------#
# Buscar el ayudante de AUR e instálar si no se encuentra. #
#----------------------------------------------------------#
printf "$NOTA - Se requiere Yay para instalar algunos paquetes desde AUR. Verificando si se encuentra instalado...\n"
sleep 2

ISYAY=/sbin/yay
if [ -f "$ISYAY" ]; then 
    echo -e "$OK - Yay, el ayudante de AUR ya está instalado. Continuando con la ejecución del script...\n"
else 
    echo -e "$AVISO - Yay, el ayudante de AUR no se encuentra instalado."
    read -n1 -rep "$OPC - ¿Le gustaría instalar yay? (y,n)" INSTYAY
    if [[ $INSTYAY =~ ^[Ss]$ ]]; then
        git clone https://aur.archlinux.org/yay-bin.git &>> $LOG
        cd yay
        makepkg -si --noconfirm &>> ../$LOG
        cd ..
        
    else
        echo -e "$ERROR - Se requiere Yay para este script, finalizando script..."
        exit
    fi
fi

# Actualizar la base de datos.
echo -e "$OK - Realizando una actualización completa del sistema..."
yay -Suy --noconfirm &>> $LOG

#----------------------------------------------------------------------------------------#
# Instalación de Hyprland, incluida la detección automática de GPU Nvidia en el sistema. #
#----------------------------------------------------------------------------------------#

if ! lspci -k | grep -A 2 -E "(VGA|3D)" | grep -iq nvidia; then
    printf "$NOTA - No se detectó GPU NVIDIA en su sistema. Instalando Hyprland sin el soporte de Nvidia..."
    sleep 2
    for HYP in hyprland; do
        yay -S $HYP 2>&1 | tee -a $LOG
    done
else
    read -n1 -rep "$OPC - GPU NVIDIA detectada. ¿Le gustaría instalar el controlador nvidia-dkms? (s/n)" NVIDIA1
    if [[ $NVIDIA1 =~ ^[Ss]$ ]]; then
      sudo pacman -R --noconfirm nvidia 2>> "$LOG" > /dev/null || true
    fi
    printf "$NOTA - Instalando nvidia-dkms...\n"
    for ndkms in linux-zen-headers nvidia-dkms nvidia-utils nvidia-settings libva; do
        yay -S $ndkms 2>&1 | tee -a "$LOG"
        if [ $? -ne 0 ]; then
            echo -e "$ERROR - $ndkms la instalación ha fallado, verifique install.log"
            exit 1
        fi
    done
    # Verificar si los módulos nvidia ya están agregados en mkinitcpio.conf y agregue si no.
    if grep -qE '^MODULES=.*nvidia. *nvidia_modeset.*nvidia_uvm.*nvidia_drm' /etc/mkinitcpio.conf; then
	    echo "Módulos de Nvidia ya incluidos en /etc/mkinitcpio.conf" 2>&1 | tee -a $LOG
    else
	    sudo sed -Ei 's/^(MODULES=\([^\)]*)\)/\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf 2>&1 | tee -a $LOG
	    echo "Módulos Nvidia agregados en /etc/mkinitcpio.conf"
    fi
    sudo mkinitcpio -P 2>&1 | tee -a $LOG
    printf "\n"   
    
    # Pasos adicionales de Nvidia.
    NVEA="/etc/modprobe.d/nvidia.conf"
    if [ -f "$NVEA" ]; then
        printf "$OK Parece que nvidia-drm modeset=1 ya está agregado en su sistema.\n"
        printf "\n"
    else
        printf "$NOTA Agregando opciones a $NVEA..."
        sudo echo -e "options nvidia-drm modeset=1" | sudo tee -a /etc/modprobe.d/nvidia.conf 2>&1 | tee -a $LOG
        printf "\n"  
    fi
    
	# Lista negra nouveau.
	read -n1 -rep "$OPC - ¿Le gustaría incluir a nouveau en la lista negra? (s/n)" nouv
	echo
	if [[ $nouv =~ ^[Ss]$ ]]; then
    	NOUVEAU="/etc/modprobe.d/nouveau.conf"
    	if [ -f "$NOUVEAU" ]; then
        	printf "$OK - Parece que nouveau ya está en la lista negra.\n"
    	else
        	echo "blacklist nouveau" | sudo tee -a "$NOUVEAU" 2>&1 | tee -a $LOG 
        	printf "$NOTA Ha sido agregado a $NOUVEAU.\n"
        	printf "\n"          

        	# A la lista negra completamente nouveau.
        	if [ -f "/etc/modprobe.d/blacklist.conf" ]; then
            	echo "install nouveau /bin/true" | sudo tee -a "/etc/modprobe.d/blacklist.conf" 2>&1 | tee -a $LOG 
        	else
            	echo "install nouveau /bin/true" | sudo tee "/etc/modprobe.d/blacklist.conf" 2>&1 | tee -a $LOG 
        	fi
    	fi
	else
    	printf "$NOTA Saltarse la lista negra de nouveau.\n"
	fi
	sleep 2
	read -n1 -rp "$OPC - GPU NVIDIA detectada. ¿Te gustaría instalar hyprland-nvidia-git? (s/n) " NVIDIA2
	if [[ $NVIDIA2 =~ ^[Ss]$ ]]; then
    	# Instalar Nvidia Hyprland
    	printf "$NOTA - Instalando hyprland-nvidia-git..."
    	if pacman -Qs hyprland > /dev/null; then
        	read -n1 -rp "$OPC - Hyprland detectado. ¿Le gustaría eliminarlo e instalar hyprland-nvidia-git en su lugar? (s,n) " hyprnvidia
        	if [[ $hyprnvidia =~ ^[Ss]$ ]]; then
    		    for hyprnvi in hyprland hyprland-git hyprland-nvidia-hidpi-git; do
        	        sudo pacman -R --noconfirm "$hyprnvi" 2>/dev/null | tee -a $LOG || true
    		    done
    	        yay -S hyprland-nvidia-git 2>&1 | tee -a $LOG
            fi
        fi
    fi
fi

#-----------------------------------#
# Instalar SDDM y Catppuccin theme. #
#-----------------------------------#
# Comprobar si SDDM ya está instalado.
if pacman -Qs sddm > /dev/null; then
    read -n1 -rep "$NOTA - SDDM ya está instalado. ¿Le gustaría desinstalar sddm e instalar sddm-git? (s/n)" sddm_git
    echo
    if [[ $sddm_git =~ ^[Ss]$ ]]; then
      sudo pacman -R --noconfirm sddm 2>> "$LOG" > /dev/null || true
    fi
    printf "$NOTA - Instalando SDDM-git...\n"
    for paquet in sddm-git; do
        yay -S $paquet 2>&1 | tee -a "$LOG"
        if [ $? -ne 0 ]; then
            echo -e "$ERROR - $paquet la instalación ha fallado, verifique install.log"
            exit 1
        fi
    done
    # Habilitar el servicio del administrador de inicio de sesión de sddm.
    echo -e "$NOTA - Habilitando el servicio SDDM..."
    for dmanager in lightdm gdm lxdm; do
        if pacman -Qs $dmanager > /dev/null; then
            sudo systemctl disable "$dmanager" 2>&1 | tee -a "$LOG"
            if [ $? -ne 0 ]; then
                echo -e "$ERROR - $dmanager no ha sido deshabilitado, verifique install.log"
                exit 1
            fi
        fi
    done
    sudo systemctl enable sddm &>> $LOG
    sleep 2
    # Configurar SDDM.
    echo -e "$NOTA Configuración de la pantalla de inicio de sesión."
    sddm_conf_dir=/etc/sddm.conf.d
    if [ ! -d "$sddm_conf_dir" ]; then
        printf "$AVISO - $sddm_conf_dir Archivo no encontrado, creando...\n"
        sudo mkdir "$sddm_conf_dir" 2>&1 | tee -a "$LOG"
    fi

    wayland_sessions_dir=/usr/share/wayland-sessions
    if [ ! -d "$wayland_sessions_dir" ]; then
        printf "$AVISO - $wayland_sessions_dir no encontrado, creando...\n"
        sudo mkdir "$wayland_sessions_dir" 2>&1 | tee -a "$LOG"
    fi
    sudo cp config/hyprland.desktop "$wayland_sessions_dir/" 2>&1 | tee -a "$LOG"
    
    # sddm-catppuccin-theme.
    read -n1 -rep "$OPC - ¿Le gustaría instalar el tema sddm catppuccin? (s/n)" instal_sddm_catppuccin
    echo

    if [[ $instal_sddm_catppuccin =~ ^[Ss]$ ]]; then
        for sddm_theme in sddm-catppuccin-git; do
            yay -S sddm_theme 2>&1 | tee -a "$LOG"
            if [ $? -ne 0 ]; then
                echo -e "$ERROR - $sddm_theme la instalación ha fallado, verifique install.log"
                exit 1
    	    fi
        done
    fi	
    echo -e "[Theme]\nCurrent=catppuccin" | sudo tee -a "$sddm_conf_dir/10-theme.conf" 2>&1 | tee -a "$LOG"
else
  printf "$NOTA SDDM no se instalará.\n"
fi

#------------------------------------#
# Comprobar si está instalada waybar #
#------------------------------------#
#Instalación de waybar.
echo "Instalando waybar..."
sudo pacman -S --noconfirm waybar
sleep 3
clear

#-------------------------------------------------#
# Deshabilitar el modo de ahorro de energía wifi. #
#-------------------------------------------------#

read -n1 -rp "$OPC - ¿Le gustaría deshabilitar el modo de ahorro de energía wifi? (s/n) " WIFI
if [[ $WIFI =~ ^[Ss]$ ]]; then
    LOC="/etc/NetworkManager/conf.d/wifi-powersave.conf"
    if [ -f "$LOC" ]; then
        printf "${OK} Parece que el ahorro de energía wifi ya está deshabilitado.\n"
        sleep 2
    else
        printf "$NOTA Se ha añadido lo siguiente a $LOC.\n"
        printf "[connection]\nwifi.powersave = 2" | sudo tee -a $LOC
        printf "$NOTA Reiniciando el servicio NetworkManager...\n"
        sudo systemctl restart NetworkManager 2>&1 | tee -a "$LOG"
        sleep 2        
    fi    
else
    printf "$NOTA El modo de ahorro de energía wifi no se desactivó.\n"
fi

######################################
### Instalar paquetes necesarios. ####
######################################

read -n1 -rep "$OPC - ¿Le gustaría instalar los componentes necesarios para hyprland? (s/n) " INST
if [[ $INST =~ ^[Ss]$ ]]; then
    #Paqueteria
    echo -e "$NOTA - Instalando los componentes principales, esto puede llevar un tiempo..."
    for SOFTWR in $(cat paqueteria.lst);
    do
        # Primero veamos si el paquete está ahí.
        if yay -Qs $SOFTWR > /dev/null ; then
            echo -e "$OK - $SOFTWR ya está instalado."
        else
            echo -e "$NOTA - Instalando $SOFTWR ..."
            yay -S --noconfirm $SOFTWR &>> $LOG
            if yay -Qs $SOFTWR > /dev/null ; then
                echo -e "$OK - $SOFTWR ha sido instalado."
            else
                echo -e "$ERROR - $SOFTWR la instalación ha fallado, verifique install.log"
                exit
            fi
        fi
    done
fi
clear

# Habilitar el servicio bluetooth.
echo -e "$NOTA - Habilitando el servicio Bluetooth..."
sudo systemctl enable --now bluetooth.service &>> $LOG
sleep 2

# Desinstalar otros portales.
echo -e "$NOTA - Limpieza de portales xdg en conflicto..."
yay -R --noconfirm xdg-desktop-portal-gnome xdg-desktop-portal-gtk &>> $LOG

### copiar archivos de configuración ###
read -n1 -rep "$OPC - ¿Le gustaría copiar archivos de configuración? (s/n) " COPIA
if [[ $COPIA == "S" || $COPIA == "s" ]]; then
    echo -e "$NOTA - Copiando archivos de configuración..."
    for DIR in hypr wofi swaylock Thunar waybar foot
    do 
        DIRPATH=~/.config/$DIR
        if [ -d "$DIRPATH" ]; then 
            echo -e "$AVISO - Config para $DIR localizado, haciendo respaldo."
            mv $DIRPATH $DIRPATH-back &>> $LOG
            echo -e "$OK - Guardado $DIR en $DIRPATH-back."
        fi
        echo -e "$NOTA - Copiando $DIR config a $DIRPATH."  
        cp -R config/$DIR ~/.config/ &>> $LOG
    done

    #mkdir -p ~/Imágenes/Wallpapers
    cp -r cosas/Wallpapers ~/Imágenes/ && { echo "¡Copia completada!"; } || { echo "Error: no se pudieron copiar los fondos de pantalla"; exit 1; } 2>&1 | tee -a "$LOG"
    echo -e "$NOTA - Establecer algunos archivos como ejecutables."
    # Dar permisos de ejecucion a los scripts. 
    chmod +x ~/.config/hypr/scripts/* 2>&1 | tee -a "$LOG"

    # Configurar el primer aspecto.
    xfconf-query -c xsettings -p /Net/ThemeName -s "Adwaita-dark"
    xfconf-query -c xsettings -p /Net/IconThemeName -s "Adwaita-dark"
    gsettings set org.gnome.desktop.interface gtk-theme "Adwaita-dark"
    gsettings set org.gnome.desktop.interface icon-theme "Adwaita-dark"
fi

### Instalar software para portátiles Asus ROG ###
read -n1 -rep "$OPC - Para portátiles ASUS ROG: ¿Le gustaría instalar el soporte de software Asus ROG? (s/n) " ROG
if [[ $ROG == "S" || $ROG == "s" ]]; then
    echo -e "$NOTA - Adding Keys..."
    sudo pacman-key --recv-keys 8F654886F17D497FEFE3DB448B15A6B0E9A3FA35 &>> $LOG
    sudo pacman-key --finger 8F654886F17D497FEFE3DB448B15A6B0E9A3FA35 &>> $LOG
    sudo pacman-key --lsign-key 8F654886F17D497FEFE3DB448B15A6B0E9A3FA35 &>> $LOG
    sudo pacman-key --finger 8F654886F17D497FEFE3DB448B15A6B0E9A3FA35 &>> $LOG

    LOC="/etc/pacman.conf"
    echo -e "$NOTA - Actualizando $LOC con repositorio g14."
    echo -e "\n[g14]\nServer = https://arch.asus-linux.org" | sudo tee -a $LOC &>> $LOG
    echo -e "\n"
    echo -e "$NOTA - Actualizando el sistema..."
    sudo pacman -Syu --noconfirm &>> $LOG

    echo -e "$NOTA - Instalando paquetes ROG..."
    sudo pacman -S --noconfirm asusctl supergfxctl rog-control-center &>> $LOG
    echo -e "$NOTA - Activando servicios ROG..."
    sudo systemctl enable --now power-profiles-daemon.service &>> $LOG
    sleep 2
    sudo systemctl enable --now supergfxd &>> $LOG
    sleep 2

    # Agregue el archivo de combinación de teclas a la configuración
    echo -e "\nsource = ~/.config/hypr/rog-g15-strix-2021-binds.conf" >> ~/.config/hypr/hyprland.conf
fi

# Script terminado #
printf "$OK Instalación completa.\n"
read -n1 -rep "$OPC ¿Le gustaría reiniciar el sistema? (s/n)" Rboot
if [[ $Rboot =~ ^[Ss]$ ]]; then
    sudo reboot 2>&1 | tee -a "$LOG"   
else
    echo "Saliendo del script..."
    exit
fi
