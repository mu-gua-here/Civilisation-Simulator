extends Node

# Used for random name generation of citizens

const FIRST_NAMES = [
	"Bartholomew", "Pickle", "Gertrude", "Wobbles", "Doug",
	"Mildred", "Chunk", "Sparkle", "Reginald", "Noodle",
	"Beatrice", "Gus", "Fizzy", "Cornelius", "Tater",
	"Velma", "Biscuit", "Engelbert", "Mochi", "Agnes",
	"Spud", "Wanda", "Pumpernickel", "Otis", "Bubbles",
	"Gravy", "Clementine", "Waffles", "Dewey", "Petunia",
	"Snorkel", "Hazel", "Boomer", "Dingo", "Florence",
	"Lumpy", "Marge", "Pickles", "Stanley", "Tofu",
	"Gizmo", "Bertha", "Chompers", "Doris", "Yeti",
	"Gumbo", "Sprinkles", "Hubert", "Nugget", "Walnut"
]

const LAST_NAMES = [
	"McSnortington", "Bumblefoot", "Von Waffle", "Garglebottom", "Crumplehorn",
	"O'Noodle", "Pickleworth", "Splatfield", "Quacksworth", "Bonkington",
	"Snugglesworth", "Fizzwhistle", "Dunkerton", "Wobblestein", "Crinklebine",
	"Sploosh", "Gargleblast", "Munchington", "Doodlesworth", "Flapjackson",
	"Stinkleberry", "Bumperton", "Snazzlebee", "Crumbcatcher", "Wigglesworth",
	"Honkington", "Toodleson", "Blobsworth", "Noodlebottom", "Squishington",
	"Farnsworth", "Yodelman", "Clumpington", "Sizzlewick", "Plopperson",
	"Gigglesworth", "Mumbleton", "Frizzlebee", "Knucklehead", "Sploshington"
]

func generate_name() -> String:
	var first = FIRST_NAMES[randi() % FIRST_NAMES.size()]
	var last = LAST_NAMES[randi() % LAST_NAMES.size()]
	return "%s %s" % [first, last]
