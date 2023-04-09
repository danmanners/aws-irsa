# Make sure that all incoming text is lower case
function lowerCaseOnly() {
    echo "$1" | tr '[upper]' '[lower]'
}

# Check if an item is in a list of arguments
function checkForItem() {
    thing="${1}"
    items="${@:2}"
    # echo "Items: $items"
    for item in $items; do
        if [[ "$item" =~ .*"$thing".* ]]; then
            echo $item
            break
        fi
    done
}

function breakApart() {
    thing=$1
    breakCharacter=$2
    echo $thing | awk -F$breakCharacter '{print $2}'
}
