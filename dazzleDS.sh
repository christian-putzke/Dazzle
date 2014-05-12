# This program is free software. It comes without any warranty, to
# the extent permitted by applicable law. You can redistribute it
# and/or modify it under the terms of the Do What The Fuck You Want
# To Public License, Version 2, as published by Sam Hocevar. See
# http://sam.zoy.org/wtfpl/COPYING for more details.
# 
# DazzleDS is based on the dazzle script from Sam Hocevar and was created
# to work with Synology NAS systems. DazzleDS was created by Christian Putzke.


# Check if we're root, if not show a warning
if [[ $USER != "root" ]]; then
  case $1 in
    ""|help) # You should be allowed to check the help without being root
      ;;
    *)
      echo "Sorry, but DazzleDS needs to be run as root."
      exit 1
      ;;
  esac
fi

GIT=`which git` > /dev/null
HOSTNAME=`grep '' /etc/hostname`

# Nice defaults
DAZZLE_USER="${DAZZLE_USER:-storage}"
DAZZLE_GROUP="${DAZZLE_GROUP:-users}"
DAZZLE_HOME="${DAZZLE_HOME:-/var/services/homes/$DAZZLE_USER}"
DAZZLE_STORAGE="${DAZZLE_STORAGE:-/var/services/homes/$DAZZLE_USER}"
DAZZLE_HOST="${DAZZLE_HOST:-$HOSTNAME}"

show_help () {
    echo "DazzleDS, SparkleShare host setup script"
    echo "This script needs to be run as root"
    echo
    echo "Usage: dazzleDS [COMMAND]"
    echo
    echo "  setup                            configures this machine to serve as a SparkleShare host"
    echo "  create PROJECT_NAME              creates a SparkleShare project called PROJECT_NAME"
    echo "  create-encrypted PROJECT_NAME    creates an encrypted SparkleShare project"
    echo "  link                             links a SparkleShare client to this host by entering a link code"
    echo
}

configure_ssh () {
  echo "  -> mkdir --parents $DAZZLE_HOME/.ssh"
  sleep 1
  mkdir -p $DAZZLE_HOME/.ssh

  echo "  -> touch $DAZZLE_HOME/.ssh/authorized_keys"
  sleep 1
  touch $DAZZLE_HOME/.ssh/authorized_keys

  echo "  -> chmod 700 $DAZZLE_HOME/.ssh"
  sleep 1
  chmod 700 $DAZZLE_HOME/.ssh

  echo "  -> chmod 600 $DAZZLE_HOME/.ssh/authorized_keys"
  sleep 1
  chmod 600 $DAZZLE_HOME/.ssh/authorized_keys

  echo "  -> chown -R $DAZZLE_USER:$DAZZLE_GROUP $DAZZLE_HOME/.ssh"
  sleep 1
  chown -R $DAZZLE_USER:$DAZZLE_GROUP $DAZZLE_HOME/.ssh

  # Disable the password for the "storage" user to force authentication using a key
  CONFIG_CHECK=`grep "^# SparkleShare$" /etc/ssh/sshd_config`
  if ! [ "$CONFIG_CHECK" = "# SparkleShare" ]; then
    echo "  -> Disable SSH password authentication for the DSM user '$DAZZLE_USER' to force authentication using a SSH-Key"
    sleep 1
    echo "" >> /etc/ssh/sshd_config
    echo "# SparkleShare" >> /etc/ssh/sshd_config
    echo "# Please do not edit the above comment as it's used as a check by Dazzle" >> /etc/ssh/sshd_config
    echo "Match User $DAZZLE_USER" >> /etc/ssh/sshd_config
    echo "    PasswordAuthentication no" >> /etc/ssh/sshd_config
    echo "    PubkeyAuthentication yes" >> /etc/ssh/sshd_config
    echo "# End of SparkleShare configuration" >> /etc/ssh/sshd_config
  fi
}

create_project () {
  if [ -f "$DAZZLE_STORAGE/$1/HEAD" ]; then
    echo "  -> Project \"$1\" already exists."
    echo
  else
    # Create the Git repository
    echo "  -> $GIT init --bare $DAZZLE_STORAGE/$1"
    $GIT init --quiet --bare "$DAZZLE_STORAGE/$1"

    # Don't allow force-pushing and data to get lost
    echo "  -> $GIT config --file $DAZZLE_STORAGE/$1/config receive.denyNonFastForwards true"
    $GIT config --file "$DAZZLE_STORAGE/$1/config" receive.denyNonFastForwards true

    # Add list of files that Git should not compress
    EXTENSIONS="jpg jpeg png tiff gif flac mp3 ogg oga avi mov mpg mpeg mkv ogv ogx webm zip gz bz bz2 rpm deb tgz rar ace 7z pak iso dmg JPG JPEG PNG TIFF GIF FLAC MP3 OGG OGA AVI MOV MPG MPEG MKV OGV OGX WEBM ZIP GZ BZ BZ2 RPM DEB TGZ RAR ACE 7Z PAK ISO DMG"
    for EXTENSION in $EXTENSIONS; do
      echo -ne "  -> echo \"*.$EXTENSION -delta\" >> $DAZZLE_STORAGE/$1/info/attributes      \r"
      echo "*.$EXTENSION -delta" >> "$DAZZLE_STORAGE/$1/info/attributes"
    done

    echo ""

    # Set the right permissions
    echo "  -> chown --recursive $DAZZLE_USER:$DAZZLE_GROUP $DAZZLE_STORAGE"
    chown -R $DAZZLE_USER:$DAZZLE_GROUP "$DAZZLE_STORAGE"

    echo "  -> chmod --recursive o-rwx $DAZZLE_STORAGE/$1"
    chmod -R o-rwx "$DAZZLE_STORAGE"/"$1"

    echo
    echo "Project \"$1\" was successfully created."
  fi

  # Fetch the external IP address
  PORT=`grep -m 1 "^Port " /etc/ssh/sshd_config | cut -b 6-`

  # Display info to link with the created project to the user
  echo "To link up a SparkleShare client, enter the following"
  echo "details into the \"Add Hosted Project...\" dialog: "
  echo
  echo "      Address: ssh://$DAZZLE_USER@$DAZZLE_HOST:$PORT"
  echo "  Remote Path: $DAZZLE_STORAGE/$1"
  echo
  echo "To link up (more) computers, use the \"dazzleDS link\" command."
  echo
}

link_client () {
  # Ask the user for the link code with a prompt
  echo "Paste your Client ID (found in the status icon menu) below and press <ENTER>."
  echo
  echo -n " Client ID: "
  read LINK_CODE

  echo $LINK_CODE >> $DAZZLE_HOME/.ssh/authorized_keys
  echo
  echo "The client with this ID can now access projects."
  echo "Repeat this step to give access to more clients."
  echo
}

check_requirements() {
  echo -n "  -> Git package ... "
  sleep 1
  if [[ $GIT == /dev/null ]]; then
    echo "not found!"
    echo "     # -------------------------------------------------------------------- #"
    echo "     # You have to install git server from the DSM Package Center at first! #"
    echo "     # Please read the README file for further information.                 #"
    echo "     # -------------------------------------------------------------------- #"
    exit 1;
  else
    echo "found!"
  fi

  USER_CHECK=`grep $DAZZLE_USER /etc/passwd | cut -c1-${#DAZZLE_USER}`
  echo -n "  -> DSM User '$DAZZLE_USER' ... "
  sleep 1
  if [ "$USER_CHECK" != "$DAZZLE_USER" ]; then
    echo "not found!"
    echo "     # ----------------------------------------------------------- #"
    echo "     # You have to create a DSM user called $DAZZLE_USER at first! #"
    echo "     # Please read the README file for further information.        #"
    echo "     # ----------------------------------------------------------- #"
    exit 1;
  else
    echo "found!"
  fi

  echo -n "  -> Home directory ... "
  sleep 1
  if ! [ -d "$DAZZLE_STORAGE" ]; then
    echo "not found!"
    echo "     # --------------------------------------------------------- #"
    echo "     # You have activate the DSM user home directories at first! #"
    echo "     # Please read the README file for further information.      #"
    echo "     # --------------------------------------------------------- #"
    exit 1;
  else
    echo "found!"
  fi

}

# Parse the command line arguments
case $1 in
  setup)
    echo " 1/2 | Checking requirements..."
    check_requirements

    sleep 1
    echo " 2/2 | Configuring DSM user SSH \"$DAZZLE_USER\"..."
    configure_ssh

    sleep 1
    echo
    echo "Setup complete! Please restart your Synology DiskStation!"
    echo "To create a new project, run \"dazzleDS create PROJECT_NAME\"."
    echo
    ;;

  create)
    if [ -n "$2" ]; then
      echo "Creating project \"$2\"..."
      create_project "$2"

    else
      echo "Please provide a project name."
    fi
    ;;

  create-encrypted)
    echo "Creating encrypted project \"$2\"..."
    create_project "$2-crypto"
    ;;

  link)
    link_client $2
    ;;

  *|help)
    show_help
    ;;
esac
